defmodule Squirrelixir.Postgres do
  @moduledoc """
  Postgrex-backed query describer for Squirrelixir inference.
  """

  alias Squirrelixir.Column
  alias Squirrelixir.Error.MissingPostgresColumn
  alias Squirrelixir.Error.MissingPostgresTable
  alias Squirrelixir.Error.PostgresInferenceError
  alias Squirrelixir.Error.PostgresSyntaxError
  alias Squirrelixir.Query
  alias Squirrelixir.TypeMapper

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
        (case when types.elem != 0 and types.name != 'name' then types.elem end, types.array_dimensions + 1),
        (case when types.kind = 'd' then types.base end, types.array_dimensions)
    ) as next_type(oid, array_dimensions)
      on next_type.oid is not null
    join pg_type
      on pg_type.oid = next_type.oid
  )
  select types.name, types.kind, types.array_dimensions
  from types
  order by types.jumps desc
  limit 1
  """

  @column_nullability_query """
  select pg_attribute.attnotnull
  from pg_attribute
  where pg_attribute.attrelid = to_regclass($1)
  and pg_attribute.attname = $2
  and pg_attribute.attnum > 0
  and not pg_attribute.attisdropped
  """

  @spec describer(Postgrex.conn()) :: Squirrelixir.Inference.describer()
  def describer(conn) do
    &describe(conn, &1)
  end

  @spec describe(Postgrex.conn(), Query.t()) :: {:ok, keyword()} | {:error, struct()}
  def describe(conn, %Query{} = query) do
    with {:ok, prepared_query} <- prepare(conn, query),
         {:ok, params} <- describe_oids(conn, prepared_query.param_oids || []),
         {:ok, returns} <- describe_returns(conn, prepared_query, query) do
      {:ok, [params: params, returns: returns]}
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

  defp describe_returns(conn, prepared_query, query) do
    columns = prepared_query.columns || []
    result_oids = prepared_query.result_oids || []
    nullability = infer_nullability(conn, query.content, columns)

    with {:ok, types} <- describe_oids(conn, result_oids) do
      returns =
        columns
        |> Enum.zip(types)
        |> Enum.with_index()
        |> Enum.map(fn {{name, type}, index} ->
          %Column{name: name, type: type, nullable?: Map.get(nullability, index, true)}
        end)

      {:ok, returns}
    end
  end

  defp infer_nullability(conn, content, columns) do
    with {:ok, tables} <- source_tables(content),
         {:ok, source_columns} <- source_columns(content, columns) do
      source_columns
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {source_column, index}, nullability ->
        Map.put(nullability, index, nullable_source_column?(conn, tables, source_column))
      end)
    else
      :error -> %{}
    end
  end

  defp source_tables(content) do
    case Regex.named_captures(
           ~r/\bfrom\s+(?<table>[a-zA-Z_][a-zA-Z0-9_\.]*)(?:\s+(?:as\s+)?(?<alias>[a-zA-Z_][a-zA-Z0-9_]*))?/i,
           content
         ) do
      %{"table" => table, "alias" => alias} ->
        tables =
          table_entries(table, alias, primary_table_nullable?(content), include_primary?: true)

        {:ok, Enum.reduce(join_tables(content), tables, &Map.merge(&2, &1))}

      nil ->
        :error
    end
  end

  defp primary_table_nullable?(content) do
    Regex.match?(~r/\b(?:right|full)\s+(?:outer\s+)?join\b/i, content)
  end

  defp join_tables(content) do
    ~r/\b(left|right|full)\s+(?:outer\s+)?join\s+([a-zA-Z_][a-zA-Z0-9_\.]*)(?:\s+(?:as\s+)?([a-zA-Z_][a-zA-Z0-9_]*))?/i
    |> Regex.scan(content)
    |> Enum.map(fn [_match, join_type, table, alias] ->
      table_entries(table, alias, joined_table_nullable?(join_type), include_primary?: false)
    end)
  end

  defp joined_table_nullable?(join_type) when join_type in ["left", "full"], do: true
  defp joined_table_nullable?(_join_type), do: false

  defp table_entries(table, alias, nullable?, opts) do
    table_info = %{table: table, nullable?: nullable?}

    [{table_name(table), table_info}, {table, table_info}]
    |> maybe_add_primary(table_info, opts)
    |> maybe_add_alias(alias, table_info)
    |> Map.new()
  end

  defp maybe_add_primary(entries, table_info, opts) do
    if Keyword.get(opts, :include_primary?, false) do
      [{:primary, table_info} | entries]
    else
      entries
    end
  end

  defp maybe_add_alias(entries, alias, _table_info) when alias in ["", nil], do: entries

  defp maybe_add_alias(entries, alias, _table_info)
       when alias in ~w(where join left right full inner outer on order group limit),
       do: entries

  defp maybe_add_alias(entries, alias, table_info), do: [{alias, table_info} | entries]

  defp table_name(table) do
    table
    |> String.split(".")
    |> List.last()
  end

  defp source_columns(content, columns) do
    with [_match, select_list] <- Regex.run(~r/\A\s*select\s+(.+?)\s+from\s+/is, content),
         source_columns when length(source_columns) == length(columns) <-
           select_list |> String.split(",") |> Enum.map(&source_column/1),
         true <- Enum.all?(source_columns, &match?({:ok, _column}, &1)) do
      {:ok, Enum.map(source_columns, fn {:ok, column} -> column end)}
    else
      _error -> :error
    end
  end

  defp source_column(select_expression) do
    select_expression = String.trim(select_expression)

    case Regex.run(
           ~r/\A(?:([a-zA-Z_][a-zA-Z0-9_]*)\.)?([a-zA-Z_][a-zA-Z0-9_]*)(?:\s+(?:as\s+)?[a-zA-Z_][a-zA-Z0-9_]*)?\z/i,
           select_expression
         ) do
      [_match, qualifier, column] when qualifier in ["", nil] -> {:ok, %{column: column}}
      [_match, qualifier, column] -> {:ok, %{qualifier: qualifier, column: column}}
      nil -> :error
    end
  end

  defp nullable_source_column?(conn, tables, %{qualifier: qualifier, column: column}) do
    case Map.fetch(tables, qualifier) do
      {:ok, %{nullable?: true}} -> true
      {:ok, %{table: table}} -> nullable_column?(conn, table, column)
      :error -> true
    end
  end

  defp nullable_source_column?(conn, tables, %{column: column}) do
    case Map.fetch(tables, :primary) do
      {:ok, %{nullable?: true}} -> true
      {:ok, %{table: table}} -> nullable_column?(conn, table, column)
      :error -> true
    end
  end

  defp nullable_column?(conn, table, column) do
    case Postgrex.query(conn, @column_nullability_query, [table, column]) do
      {:ok, %Postgrex.Result{rows: [[true]]}} -> false
      _other -> true
    end
  end

  defp describe_oids(conn, oids) do
    Enum.reduce_while(oids, {:ok, []}, fn oid, {:ok, types} ->
      case describe_oid(conn, oid) do
        {:ok, type} -> {:cont, {:ok, [type | types]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, types} -> {:ok, Enum.reverse(types)}
      {:error, error} -> {:error, error}
    end
  end

  defp describe_oid(conn, oid) do
    with {:ok, %Postgrex.Result{rows: [[name, kind, array_dimensions]]}} <-
           Postgrex.query(conn, @type_lookup_query, [oid]) do
      TypeMapper.from_postgres(name, kind: kind, array_dimensions: array_dimensions)
    end
  end
end
