defmodule Squirrelixir.Postgres do
  @moduledoc """
  Postgrex-backed query inferrer for SquirrElix inference.
  """

  alias Squirrelixir.Column
  alias Squirrelixir.Error.MissingPostgresColumn
  alias Squirrelixir.Error.MissingPostgresTable
  alias Squirrelixir.Error.PostgresInferenceError
  alias Squirrelixir.Error.PostgresSyntaxError
  alias Squirrelixir.Error.QueryHasInvalidEnum
  alias Squirrelixir.Query
  alias Squirrelixir.TypeMapper

  @column_nullability_query """
  select a.attnotnull
  from pg_attribute a
  join pg_class c on a.attrelid = c.oid
  join pg_namespace n on c.relnamespace = n.oid
  where c.relname = $1
    and a.attname = $2
    and a.attnum > 0
    and not a.attisdropped
    and n.nspname = any(current_schemas(true))
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

  @spec inferrer(Postgrex.conn()) :: Squirrelixir.Inference.inferrer()
  def inferrer(conn) do
    &infer(conn, &1)
  end

  @spec infer(Postgrex.conn(), Query.t()) :: {:ok, keyword()} | {:error, struct()}
  def infer(conn, %Query{} = query) do
    with {:ok, prepared_query} <- prepare(conn, query),
         {:ok, params} <- describe_oids(conn, prepared_query.param_oids || [], query),
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

    {plan_available?, plan_nullables, column_sources} =
      infer_nullability(conn, query, prepared_query)

    with {:ok, types} <- describe_oids(conn, result_oids, query) do
      returns =
        columns
        |> Enum.zip(types)
        |> Enum.with_index()
        |> Enum.map(fn {{name, type}, index} ->
          nullable? =
            column_nullable?(
              conn,
              name,
              index,
              plan_nullables,
              column_sources,
              plan_available?
            )

          %Column{name: name, type: type, nullable?: nullable?}
        end)

      {:ok, returns}
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
    explain_query =
      "explain (format json, verbose, generic_plan) " <> explainable_query_content(query.content)

    with {:ok, %Postgrex.Result{rows: [[plan_json]]}} <-
           Postgrex.query(conn, explain_query, [], query_type: :text),
         {:ok, root_plan} <- decode_plan_json(plan_json) do
      {:ok, parse_plan(root_plan)}
    else
      _ -> :error
    end
  end

  defp explainable_query_content(content) do
    content
    |> String.trim_leading()
    |> String.replace(~r/^;+\s*/, "")
  end

  defp decode_plan_json(plan_json) when is_binary(plan_json) do
    with {:ok, data} <- Jason.decode(plan_json) do
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
      Map.get(expr_to_source, expr) || parse_qualified_expr(expr)
    end)
  end

  defp collect_expr_sources(%{relation: relation, output: output, plans: plans})
       when is_binary(relation) and relation != "" do
    own =
      output
      |> Enum.map(fn expr -> {expr, {relation, column_from_expr(expr, relation)}} end)
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

  defp parse_qualified_expr(expr) do
    case String.split(expr, ".") do
      [table, column] -> {table, column}
      _ -> nil
    end
  end

  defp column_from_expr(expr, default_table) do
    case String.split(expr, ".") do
      [_table, column] -> column
      [column] -> column
      _ -> default_table
    end
  end

  defp column_nullable?(conn, name, index, plan_nullables, column_sources, plan_available?) do
    cond do
      String.ends_with?(name, "!") ->
        false

      String.ends_with?(name, "?") ->
        true

      MapSet.member?(plan_nullables, index) ->
        true

      true ->
        case Enum.at(column_sources, index) do
          {table, column} -> !column_has_not_null_constraint?(conn, table, column)
          nil -> !plan_available?
        end
    end
  end

  defp column_has_not_null_constraint?(conn, table, column) do
    case Postgrex.query(conn, @column_nullability_query, [table, column]) do
      {:ok, %Postgrex.Result{rows: [[true]]}} -> true
      {:ok, %Postgrex.Result{rows: [[false]]}} -> false
      _ -> false
    end
  end

  defp describe_oids(conn, oids, query) do
    Enum.reduce_while(oids, {:ok, []}, fn oid, {:ok, types} ->
      case describe_oid(conn, oid, query) do
        {:ok, type} -> {:cont, {:ok, [type | types]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, types} -> {:ok, Enum.reverse(types)}
      {:error, error} -> {:error, error}
    end
  end

  defp describe_oid(conn, oid, query) do
    with {:ok, %Postgrex.Result{rows: [[name, kind, array_dimensions, type_oid]]}} <-
           Postgrex.query(conn, @type_lookup_query, [oid]) do
      resolve_postgres_type(conn, type_oid, name, kind, array_dimensions, query)
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
