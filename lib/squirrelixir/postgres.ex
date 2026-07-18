defmodule Squirrelixir.Postgres do
  @moduledoc """
  Postgrex-backed query describer for Squirrelixir inference.
  """

  alias Squirrelixir.Column
  alias Squirrelixir.Query
  alias Squirrelixir.TypeMapper

  @type_lookup_query """
  with recursive types as (
    select
      pg_type.oid as oid,
      pg_type.typname as name,
      pg_type.typelem as elem,
      0 as jumps
    from pg_type
    where pg_type.oid = $1::oid
  union all
    select
      pg_type.oid as oid,
      pg_type.typname as name,
      pg_type.typelem as elem,
      types.jumps + 1 as jumps
    from pg_type
    join types
      on pg_type.oid = types.elem
      and types.name != 'name'
  )
  select types.name, types.jumps
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
         {:ok, returns} <- describe_returns(conn, prepared_query) do
      {:ok, [params: params, returns: returns]}
    end
  end

  defp prepare(conn, query) do
    Postgrex.prepare(conn, "", query.content)
  end

  defp describe_returns(conn, prepared_query) do
    columns = prepared_query.columns || []
    result_oids = prepared_query.result_oids || []

    with {:ok, types} <- describe_oids(conn, result_oids) do
      returns =
        columns
        |> Enum.zip(types)
        |> Enum.map(fn {name, type} -> %Column{name: name, type: type, nullable?: true} end)

      {:ok, returns}
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
    with {:ok, %Postgrex.Result{rows: [[name, array_dimensions]]}} <-
           Postgrex.query(conn, @type_lookup_query, [oid]) do
      TypeMapper.from_postgres(name, array_dimensions: array_dimensions)
    end
  end
end
