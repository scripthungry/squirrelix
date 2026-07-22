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
    nullability = infer_nullability(conn, query, columns)

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

  # -- Plan-based nullability inference (mirrors upstream Gleam squirrel) --

  defp infer_nullability(conn, query, columns) do
    case query_plan(conn, query) do
      {:ok, plan} -> nullables_from_plan(plan, columns)
      :error -> %{}
    end
  end

  defp query_plan(conn, query) do
    # EXPLAIN doesn't work with parameterized queries ($1, $2).
    # Skip plan-based nullability for parameterized queries; fall back to default (all nullable).
    if String.contains?(query.content, "$") do
      :error
    else
      explain_query = "explain (format json, verbose) " <> query.content

      case Postgrex.query(conn, explain_query, []) do
        {:ok, %Postgrex.Result{rows: [[plan_json]]}} ->
          # Postgrex JSON extension may auto-decode; handle both string and map
          plan_data =
            case plan_json do
              s when is_binary(s) ->
                case Jason.decode(s) do
                  {:ok, data} -> data
                  _ -> :error
                end
              data when is_list(data) -> data
              data when is_map(data) -> data
            end

          case plan_data do
            [%{"Plan" => root_plan} | _] ->
              {:ok, parse_plan(root_plan)}
            %{"Plan" => root_plan} ->
              {:ok, parse_plan(root_plan)}
            _ ->
              :error
          end

        {:error, _} ->
          :error
      end
    end
  end

  defp parse_plan(plan_map) do
    %{
      join_type: Map.get(plan_map, "Join Type"),
      output: Map.get(plan_map, "Output", []),
      plans: plan_map |> Map.get("Plans", []) |> Enum.map(&parse_plan/1)
    }
  end

  defp nullables_from_plan(plan, _columns) do
    # Build a map from output expression string to column index
    # from the root plan's output (these are the query-level column expressions)
    outputs =
      plan.output
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {expr, idx}, acc -> Map.put(acc, expr, idx) end)

    do_nullables_from_plan(plan, outputs, MapSet.new())
    |> MapSet.to_list()
    |> Enum.reduce(%{}, fn idx, acc -> Map.put(acc, idx, true) end)
  end

  defp do_nullables_from_plan(plan, query_outputs, nullables) do
    case {plan.join_type, plan.plans} do
      # Full join → all outputs are nullable
      {"Full Join", _} ->
        plan_outputs_indices(plan, query_outputs)
        |> MapSet.union(nullables)

      # Right join → left (outer) side outputs are nullable
      {"Right Join", [left, right]} ->
        nullables =
          plan_outputs_indices(left, query_outputs)
          |> MapSet.union(nullables)

        do_nullables_from_plan(right, query_outputs, nullables)

      # Left join / Semi join → right (inner) side outputs are nullable
      {"Left Join", [left, right]} ->
        nullables =
          plan_outputs_indices(right, query_outputs)
          |> MapSet.union(nullables)

        do_nullables_from_plan(left, query_outputs, nullables)

      {"Semi Join", [left, right]} ->
        nullables =
          plan_outputs_indices(right, query_outputs)
          |> MapSet.union(nullables)

        do_nullables_from_plan(left, query_outputs, nullables)

      # Inner join → recurse into children
      {"Inner Join", plans} ->
        Enum.reduce(plans, nullables, fn child, acc ->
          do_nullables_from_plan(child, query_outputs, acc)
        end)

      # Leaf node or unexpected cardinality → recurse into children
      {_join_type, plans} ->
        Enum.reduce(plans, nullables, fn child, acc ->
          do_nullables_from_plan(child, query_outputs, acc)
        end)
    end
  end

  defp plan_outputs_indices(plan, query_outputs) do
    # Match this plan node's output expressions against the top-level query outputs.
    # If a match is found, that column index is marked nullable.
    Enum.reduce(plan.output, MapSet.new(), fn output, acc ->
      case Map.fetch(query_outputs, output) do
        {:ok, idx} -> MapSet.put(acc, idx)
        :error -> acc
      end
    end)
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
