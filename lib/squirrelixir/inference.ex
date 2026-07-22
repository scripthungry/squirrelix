defmodule Squirrelixir.Inference.Inferrer do
  @moduledoc """
  Behaviour for modules that infer SQL query parameters and returned columns.

  The Mix task uses `Squirrelixir.Postgres.inferrer/1` when `--infer` is passed.
  See the [Configuration guide](configuration.html) for connection options.
  """

  @callback infer(Squirrelixir.Query.t()) :: {:ok, keyword()} | {:error, struct()}
end

defmodule Squirrelixir.Inference do
  @moduledoc """
  Converts parsed query directories into typed query directories using an inferrer callback.

  Used by `Squirrelixir.generate/3` and `Squirrelixir.check/3` when the query source
  is a function or `Squirrelixir.Inference.Inferrer` module rather than a metadata map.
  See [Configuration](configuration.html) for metadata vs inference modes.
  """

  alias Squirrelixir.Error
  alias Squirrelixir.Query
  alias Squirrelixir.QueryDirectory
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

  @type inferrer :: (Query.t() -> {:ok, keyword()} | {:error, struct()}) | module()

  @spec from_query_directories([QueryDirectory.t()], inferrer()) :: [TypedQueryDirectory.t()]
  def from_query_directories(query_directories, inferrer) when is_list(query_directories) do
    query_directories
    |> Enum.sort_by(& &1.directory)
    |> Enum.map(&from_query_directory(&1, inferrer))
  end

  defp from_query_directory(%QueryDirectory{} = query_directory, inferrer) do
    {typed_queries, errors} =
      Enum.reduce(query_directory.queries, {[], query_directory.errors}, fn query, acc ->
        infer_query(query, inferrer, acc)
      end)

    %TypedQueryDirectory{
      directory: query_directory.directory,
      queries: Enum.reverse(typed_queries),
      errors: Enum.map(errors, &Error.normalize/1)
    }
  end

  defp infer_query(query, inferrer, {typed_queries, errors}) do
    case call_inferrer(inferrer, query) do
      {:ok, metadata} ->
        typed_query_from_metadata(query, metadata, typed_queries, errors)

      {:error, error} ->
        {typed_queries, errors ++ [error |> Error.attach_query(query) |> Error.normalize()]}
    end
  end

  defp call_inferrer(inferrer, query) when is_function(inferrer, 1) do
    inferrer.(query)
  end

  defp call_inferrer(inferrer, query) when is_atom(inferrer) do
    inferrer.infer(query)
  end

  defp typed_query_from_metadata(query, metadata, typed_queries, errors) do
    case TypedQuery.from_query(query, metadata) do
      {:ok, typed_query} -> {[typed_query | typed_queries], errors}
      {:error, error} -> {typed_queries, errors ++ [Error.attach_query(error, query)]}
    end
  end
end
