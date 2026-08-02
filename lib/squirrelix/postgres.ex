defmodule Squirrelix.Postgres do
  @moduledoc """
  Postgrex-backed query inferrer.

  ## Supported public API

  * `inferrer/1` — build a query-source inferrer for `Squirrelix.generate/3` /
    `check/3` from an open `Postgrex.conn()`

  Other functions in this module are internal and may change without notice.
  Connection resolution for Mix tasks is documented in the Configuration guide;
  do not call Mix-oriented helpers from application code.
  """

  alias Squirrelix.Column
  alias Squirrelix.ConnectionOptions
  alias Squirrelix.Error
  alias Squirrelix.Error.MissingPostgresColumn
  alias Squirrelix.Error.MissingPostgresTable
  alias Squirrelix.Error.PostgresInferenceError
  alias Squirrelix.Error.PostgresSyntaxError
  alias Squirrelix.Error.QueryHasInvalidEnum
  alias Squirrelix.Error.QueryHasMultipleStatements
  alias Squirrelix.Error.UnsupportedPostgresVersion
  alias Squirrelix.Query
  alias Squirrelix.SQL
  alias Squirrelix.TypeMapper

  require Logger

  # `EXPLAIN … generic_plan` (nullability) requires Postgres 16+.
  @minimum_server_version_num 160_000

  # $1 = relation name, $2 = column name, $3 = schema (NULL = search_path / temp).
  @column_nullability_query """
  select a.attnotnull
  from pg_attribute a
  join pg_class c on a.attrelid = c.oid
  join pg_namespace n on c.relnamespace = n.oid
  where c.relname = $1
    and a.attname = $2
    and a.attnum > 0
    and not a.attisdropped
    and (
      case
        when $3::text is null then n.nspname = any(current_schemas(true))
        when $3::text = 'pg_temp' or $3::text like 'pg_temp_%' then
          n.oid = pg_my_temp_schema()
        else n.nspname = $3
      end
    )
  limit 1
  """

  @type_lookup_query """
  with recursive types(oid, name, elem, kind, base, array_dimensions, jumps) as (
    select
      pg_type.oid as oid,
      pg_type.typname as name,
      pg_type.typelem as elem,
      pg_type.typtype as kind,
      pg_type.typbasetype as base,
      0 as array_dimensions,
      0 as jumps
    from pg_type
    where pg_type.oid = $1::oid
  union all
    select
      pg_type.oid as oid,
      pg_type.typname as name,
      pg_type.typelem as elem,
      pg_type.typtype as kind,
      pg_type.typbasetype as base,
      next_type.array_dimensions as array_dimensions,
      types.jumps + 1 as jumps
    from types
    join lateral (
      values
        (case when types.elem != 0 and types.name not in ('name', 'point') then types.elem end, types.array_dimensions + 1),
        (case when types.kind = 'd' then types.base end, types.array_dimensions)
    ) as next_type(oid, array_dimensions)
      on next_type.oid is not null
    join pg_type
      on pg_type.oid = next_type.oid
  )
  select types.name, types.kind, types.array_dimensions, types.oid
  from types
  order by types.jumps desc
  limit 1
  """

  @enum_variants_query """
  select enumlabel
  from pg_enum
  where enumtypid = $1::oid
  order by enumsortorder asc
  """

  @doc false
  @spec minimum_server_version_num() :: pos_integer()
  def minimum_server_version_num, do: @minimum_server_version_num

  @doc false
  @spec server_version_supported?(non_neg_integer()) :: boolean()
  def server_version_supported?(version_num) when is_integer(version_num) and version_num >= 0 do
    version_num >= @minimum_server_version_num
  end

  @doc false
  @spec unsupported_server_version_error(ConnectionOptions.t(), non_neg_integer()) ::
          UnsupportedPostgresVersion.t()
  def unsupported_server_version_error(%ConnectionOptions{} = opts, version_num)
      when is_integer(version_num) and version_num >= 0 do
    %UnsupportedPostgresVersion{
      host: opts.host,
      port: opts.port,
      version_num: version_num,
      minimum_version_num: @minimum_server_version_num
    }
  end

  @doc false
  @spec connect(ConnectionOptions.t()) :: {:ok, pid()} | {:error, struct()}
  def connect(%ConnectionOptions{} = connection_options) do
    postgrex_opts = postgrex_opts(connection_options)

    case probe_connection(postgrex_opts) do
      :ok ->
        case Postgrex.start_link(postgrex_opts) do
          {:ok, conn} ->
            ensure_supported_server_version(conn, connection_options)

          {:error, reason} ->
            {:error, Error.connection_error(reason, connection_options)}
        end

      {:error, reason} ->
        {:error, Error.connection_error(reason, connection_options)}
    end
  end

  defp ensure_supported_server_version(conn, %ConnectionOptions{} = connection_options) do
    case fetch_server_version_num(conn) do
      {:ok, version_num} ->
        if server_version_supported?(version_num) do
          {:ok, conn}
        else
          _ = GenServer.stop(conn)
          {:error, unsupported_server_version_error(connection_options, version_num)}
        end

      {:error, reason} ->
        _ = GenServer.stop(conn)
        {:error, Error.connection_error(reason, connection_options)}
    end
  end

  defp fetch_server_version_num(conn) do
    case Postgrex.query(conn, "select current_setting('server_version_num')", []) do
      {:ok, %Postgrex.Result{rows: [[version]]}} when is_binary(version) ->
        case Integer.parse(version) do
          {version_num, ""} -> {:ok, version_num}
          _invalid -> {:error, {:invalid_server_version_num, version}}
        end

      {:ok, other} ->
        {:error, {:unexpected_server_version_result, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns an inferrer function for `Squirrelix.generate/3` / `check/3`.

  The returned function takes a `Squirrelix.Query` and returns
  `{:ok, [params: ..., returns: ...]}` or `{:error, structured_error}`.

  OID→type and column-nullability catalog lookups are memoised for the lifetime
  of the returned function so a generate/check pass does not re-query the same
  catalog rows for every parameter and column.
  """
  @spec inferrer(Postgrex.conn()) :: Squirrelix.Inference.inferrer()
  def inferrer(conn) do
    cache_key = {__MODULE__, :catalog_cache, make_ref()}

    fn query ->
      cache = Process.get(cache_key) || new_catalog_cache()

      case infer(conn, query, cache) do
        {:ok, result, cache} ->
          Process.put(cache_key, cache)
          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc false
  @spec infer(Postgrex.conn(), Query.t()) :: {:ok, keyword()} | {:error, struct()}
  def infer(conn, %Query{} = query) do
    case infer(conn, query, new_catalog_cache()) do
      {:ok, result, _cache} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  defp infer(conn, %Query{} = query, cache) do
    with :ok <- ensure_single_statement(query),
         {:ok, prepared_query} <- prepare(conn, query),
         {:ok, params, cache} <-
           describe_oids(conn, prepared_query.param_oids || [], query, cache),
         {:ok, returns, cache} <- describe_returns(conn, prepared_query, query, cache) do
      {:ok, [params: params, returns: returns], cache}
    end
  end

  defp new_catalog_cache do
    %{oids: %{}, columns: %{}}
  end

  defp ensure_single_statement(%Query{} = query) do
    if SQL.single_statement?(query.content) do
      :ok
    else
      {:error,
       %QueryHasMultipleStatements{
         file: query.file,
         starting_line: query.starting_line,
         content: query.content
       }}
    end
  end

  @doc false
  @spec postgrex_opts(ConnectionOptions.t()) :: keyword()
  def postgrex_opts(%ConnectionOptions{} = connection_options) do
    [
      hostname: connection_options.host,
      port: connection_options.port,
      username: connection_options.user,
      password: connection_options.password,
      database: connection_options.database,
      timeout: connection_options.timeout_seconds * 1000,
      connect_timeout: connection_options.timeout_seconds * 1000,
      ssl: connection_options.ssl || false,
      types: Postgrex.DefaultTypes
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp probe_connection(opts) do
    case Postgrex.Protocol.connect(opts) do
      {:ok, state} ->
        _ =
          Postgrex.Protocol.disconnect(
            %DBConnection.ConnectionError{message: "squirrelix connection probe"},
            state
          )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare(conn, query) do
    case Postgrex.prepare(conn, "", query.content) do
      {:ok, prepared_query} -> {:ok, prepared_query}
      {:error, %Postgrex.Error{} = error} -> {:error, postgres_error(query, error)}
    end
  end

  defp postgres_error(query, %Postgrex.Error{postgres: %{code: :syntax_error} = postgres}) do
    %PostgresSyntaxError{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content,
      message: postgres.message,
      position: parse_position(postgres)
    }
  end

  defp postgres_error(query, %Postgrex.Error{postgres: %{code: :undefined_table} = postgres}) do
    %MissingPostgresTable{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content,
      message: postgres.message,
      table: quoted_identifier(postgres.message),
      position: parse_position(postgres)
    }
  end

  defp postgres_error(query, %Postgrex.Error{postgres: %{code: :undefined_column} = postgres}) do
    %MissingPostgresColumn{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content,
      message: postgres.message,
      column: quoted_identifier(postgres.message),
      position: parse_position(postgres)
    }
  end

  defp postgres_error(query, %Postgrex.Error{postgres: postgres}) do
    %PostgresInferenceError{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content,
      message: Map.get(postgres, :message, "Postgres rejected query inference"),
      code: Map.get(postgres, :code),
      position: parse_position(postgres)
    }
  end

  defp parse_position(%{position: position}) when is_binary(position) do
    case Integer.parse(position) do
      {value, ""} -> value
      _invalid -> nil
    end
  end

  defp parse_position(_postgres), do: nil

  defp quoted_identifier(message) when is_binary(message) do
    case Regex.run(~r/"([^"]+)"/, message) do
      [_match, identifier] -> identifier
      nil -> nil
    end
  end

  defp quoted_identifier(_message), do: nil

  defp describe_returns(conn, prepared_query, query, cache) do
    columns = prepared_query.columns || []
    result_oids = prepared_query.result_oids || []

    {plan_available?, plan_nullables, column_sources} =
      infer_nullability(conn, query, prepared_query)

    # Tuple index is O(1); the former Enum.at/2 on the list was O(C) per column.
    column_sources = List.to_tuple(column_sources)

    with {:ok, types, cache} <- describe_oids(conn, result_oids, query, cache) do
      {returns, cache} =
        columns
        |> Enum.zip(types)
        |> Enum.with_index()
        |> Enum.map_reduce(cache, fn {{name, type}, index}, cache ->
          {nullable?, cache} =
            column_nullable?(
              conn,
              name,
              index,
              plan_nullables,
              column_sources,
              plan_available?,
              cache
            )

          {%Column{
             name: strip_nullability_override(name),
             type: type,
             nullable?: nullable?
           }, cache}
        end)

      {:ok, returns, cache}
    end
  end

  # -- Plan-based nullability inference (mirrors upstream Gleam squirrel) --

  defp infer_nullability(conn, query, _prepared_query) do
    case query_plan(conn, query) do
      {:ok, plan} ->
        {true, nullables_from_plan(plan), column_sources_from_plan(plan)}

      :error ->
        {false, MapSet.new(), []}
    end
  end

  defp query_plan(conn, query) do
    content = explainable_query_content(query.content)

    # Multi-statement SQL is rejected in `infer/2` / `Query.from_file/1`.
    # Simple protocol is required so `$n` placeholders work with `generic_plan`
    # without binding params.
    explain_query = "explain (format json, verbose, generic_plan) " <> content

    try do
      with {:ok, %Postgrex.Result{rows: [[plan_json]]}} <-
             explain_json_query(conn, explain_query),
           {:ok, root_plan} <- decode_plan_json(plan_json) do
        {:ok, parse_plan(root_plan)}
      else
        _ ->
          warn_explain_unavailable(query.file)
          :error
      end
    rescue
      _e in [DBConnection.ConnectionError, Postgrex.Error, ArgumentError] ->
        warn_explain_unavailable(query.file)
        :error
    end
  end

  # `query_type: :text` is documented by Postgrex but missing from `execute_option()`,
  # so a direct call makes Dialyzer treat the success path as impossible.
  defp explain_json_query(conn, explain_query) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(Postgrex, :query, [conn, explain_query, [], [query_type: :text]])
  end

  defp warn_explain_unavailable(file) do
    Logger.warning(
      "Squirrelix: EXPLAIN nullability unavailable for #{file}; " <>
        "treating unknown columns as nullable (override with \"name!\" / \"name?\" aliases if needed)"
    )
  end

  defp explainable_query_content(content) do
    content
    |> String.trim_leading()
    |> String.replace(~r/^;+\s*/, "")
  end

  defp decode_plan_json(plan_json) when is_binary(plan_json) do
    with {:ok, data} <- JSON.decode(plan_json) do
      decode_plan_json(data)
    end
  end

  defp decode_plan_json([%{"Plan" => root_plan} | _]), do: {:ok, root_plan}
  defp decode_plan_json(%{"Plan" => root_plan}), do: {:ok, root_plan}
  defp decode_plan_json(_), do: :error

  defp parse_plan(plan_map) do
    %{
      join_type: Map.get(plan_map, "Join Type"),
      output: Map.get(plan_map, "Output", []),
      relation: Map.get(plan_map, "Relation Name"),
      schema: Map.get(plan_map, "Schema"),
      plans: plan_map |> Map.get("Plans", []) |> Enum.map(&parse_plan/1)
    }
  end

  defp nullables_from_plan(plan) do
    outputs =
      plan.output
      |> Enum.with_index()
      |> Map.new(fn {expr, idx} -> {expr, idx} end)

    do_nullables_from_plan(plan, outputs, MapSet.new())
  end

  defp do_nullables_from_plan(plan, query_outputs, nullables) do
    case {plan.join_type, plan.plans} do
      {"Full", _} ->
        plan_outputs_indices(plan, query_outputs)
        |> MapSet.union(nullables)

      {"Right", [left, right]} ->
        nullables =
          plan_outputs_indices(left, query_outputs)
          |> MapSet.union(nullables)

        do_nullables_from_plan(right, query_outputs, nullables)

      {"Left", [left, right]} ->
        nullables =
          plan_outputs_indices(right, query_outputs)
          |> MapSet.union(nullables)

        do_nullables_from_plan(left, query_outputs, nullables)

      {"Semi", [left, right]} ->
        nullables =
          plan_outputs_indices(right, query_outputs)
          |> MapSet.union(nullables)

        do_nullables_from_plan(left, query_outputs, nullables)

      {"Inner", plans} ->
        Enum.reduce(plans, nullables, fn child, acc ->
          do_nullables_from_plan(child, query_outputs, acc)
        end)

      {_, plans} ->
        Enum.reduce(plans, nullables, fn child, acc ->
          do_nullables_from_plan(child, query_outputs, acc)
        end)
    end
  end

  defp plan_outputs_indices(plan, query_outputs) do
    Enum.reduce(plan.output, MapSet.new(), fn output, acc ->
      case Map.fetch(query_outputs, output) do
        {:ok, idx} -> MapSet.put(acc, idx)
        :error -> acc
      end
    end)
  end

  defp column_sources_from_plan(plan) do
    expr_to_source = collect_expr_sources(plan)

    Enum.map(plan.output, fn expr ->
      Map.get(expr_to_source, expr) || classify_output_expr(expr, nil, nil)
    end)
  end

  defp collect_expr_sources(%{relation: relation, schema: schema, output: output, plans: plans})
       when is_binary(relation) and relation != "" do
    own =
      output
      |> Enum.map(fn expr -> {expr, classify_output_expr(expr, schema, relation)} end)
      |> Map.new()

    Enum.reduce(plans, own, fn child, acc ->
      Map.merge(acc, collect_expr_sources(child))
    end)
  end

  defp collect_expr_sources(%{plans: plans}) do
    Enum.reduce(plans, %{}, fn child, acc ->
      Map.merge(acc, collect_expr_sources(child))
    end)
  end

  # Classify EXPLAIN "Output" entries into table columns, scalar subplans, or
  # expression-derived values. Matches Gleam squirrel's table_oid=0 behaviour
  # for expressions (non-nullable) while treating SubPlan outputs as nullable.
  defp classify_output_expr(expr, schema, relation) when is_binary(expr) do
    if Regex.match?(~r/^\(SubPlan \d+\)$/, expr) do
      :subquery
    else
      table_column_source(expr, schema, relation) || :expression
    end
  end

  defp classify_output_expr(_expr, _schema, _relation), do: :expression

  defp table_column_source(expr, schema, relation) do
    with {:ok, column} <- parse_column_ref(expr),
         table when is_binary(table) <- relation || table_from_qualified_expr(expr) do
      {:table_column, schema, table, column}
    else
      _ -> nil
    end
  end

  defp parse_column_ref(expr) do
    # Optional alias/table qualifier, then a single identifier (quoted or bare).
    # Anything else (operators, function calls, casts) is an expression.
    case Regex.run(
           ~r/^((?:[A-Za-z_][A-Za-z0-9_]*|"[^"]+")\.)?([A-Za-z_][A-Za-z0-9_]*|"[^"]+")$/,
           expr
         ) do
      [_match, _qualifier, column] -> {:ok, unquote_ident(column)}
      nil -> :error
    end
  end

  defp table_from_qualified_expr(expr) do
    case String.split(expr, ".", parts: 2) do
      [table, _column] -> unquote_ident(table)
      _ -> nil
    end
  end

  defp unquote_ident(<<"\"", rest::binary>>) do
    String.trim_trailing(rest, "\"")
  end

  defp unquote_ident(ident), do: ident

  defp column_nullable?(
         conn,
         name,
         index,
         plan_nullables,
         column_sources,
         plan_available?,
         cache
       ) do
    cond do
      String.ends_with?(name, "!") ->
        {false, cache}

      String.ends_with?(name, "?") ->
        {true, cache}

      MapSet.member?(plan_nullables, index) ->
        {true, cache}

      true ->
        source_nullable?(conn, column_source_at(column_sources, index), plan_available?, cache)
    end
  end

  defp column_source_at(sources, index)
       when is_tuple(sources) and is_integer(index) and index >= 0 do
    if index < tuple_size(sources), do: elem(sources, index), else: nil
  end

  # Trailing `!` / `?` aliases force nullability (above); strip before TypedQuery
  # identifier validation so generated map keys stay valid Elixir atoms.
  defp strip_nullability_override(name) when is_binary(name) do
    cond do
      String.ends_with?(name, "!") -> String.replace_suffix(name, "!", "")
      String.ends_with?(name, "?") -> String.replace_suffix(name, "?", "")
      true -> name
    end
  end

  defp source_nullable?(_conn, :subquery, _plan_available?, cache), do: {true, cache}
  defp source_nullable?(_conn, :expression, _plan_available?, cache), do: {false, cache}

  defp source_nullable?(conn, {:table_column, schema, table, column}, _plan_available?, cache)
       when is_binary(table) and is_binary(column) do
    {not_null?, cache} = column_has_not_null_constraint?(conn, schema, table, column, cache)
    {!not_null?, cache}
  end

  defp source_nullable?(_conn, _other, plan_available?, cache), do: {!plan_available?, cache}

  defp column_has_not_null_constraint?(conn, schema, table, column, cache) do
    key = {schema, table, column}

    case Map.fetch(cache.columns, key) do
      {:ok, value} ->
        {value, cache}

      :error ->
        value =
          case Postgrex.query(conn, @column_nullability_query, [table, column, schema]) do
            {:ok, %Postgrex.Result{rows: [[true]]}} -> true
            {:ok, %Postgrex.Result{rows: [[false]]}} -> false
            _ -> false
          end

        {value, %{cache | columns: Map.put(cache.columns, key, value)}}
    end
  end

  defp describe_oids(conn, oids, query, cache) do
    Enum.reduce_while(oids, {:ok, [], cache}, fn oid, {:ok, types, cache} ->
      case describe_oid(conn, oid, query, cache) do
        {:ok, type, cache} -> {:cont, {:ok, [type | types], cache}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, types, cache} -> {:ok, Enum.reverse(types), cache}
      {:error, error} -> {:error, error}
    end
  end

  defp describe_oid(conn, oid, query, cache) do
    case Map.fetch(cache.oids, oid) do
      {:ok, type} ->
        {:ok, type, cache}

      :error ->
        with {:ok, %Postgrex.Result{rows: [[name, kind, array_dimensions, type_oid]]}} <-
               Postgrex.query(conn, @type_lookup_query, [oid]),
             {:ok, type} <-
               resolve_postgres_type(conn, type_oid, name, kind, array_dimensions, query) do
          {:ok, type, %{cache | oids: Map.put(cache.oids, oid, type)}}
        end
    end
  end

  defp resolve_postgres_type(conn, oid, name, "e", array_dimensions, query) do
    with {:ok, variants} <- enum_variants(conn, oid),
         :ok <- TypeMapper.validate_enum(name, variants),
         {:ok, type} <-
           TypeMapper.from_postgres(name, kind: "e", array_dimensions: array_dimensions) do
      {:ok, type}
    else
      {:error, :no_variants} ->
        {:error, invalid_enum_error(query, name, :no_variants)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp resolve_postgres_type(_conn, _oid, name, kind, array_dimensions, _query) do
    TypeMapper.from_postgres(name, kind: kind, array_dimensions: array_dimensions)
  end

  defp enum_variants(conn, oid) do
    case Postgrex.query(conn, @enum_variants_query, [oid]) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        {:ok, Enum.map(rows, fn [variant] -> variant end)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp invalid_enum_error(query, enum_name, reason) do
    %QueryHasInvalidEnum{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content,
      enum_name: enum_name,
      reason: reason
    }
  end
end
