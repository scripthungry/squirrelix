defmodule Squirrelix.Inference.Inferrer do
  @moduledoc """
  Behaviour for modules that infer SQL query parameters and returned columns.

  Part of the supported public API for custom query sources. Prefer
  `Squirrelix.Postgres.inferrer/1` when connecting to a live database.

  Callbacks receive a `Squirrelix.Query` and must return either:

      {:ok, [params: types, returns: columns]}
      {:error, structured_error}

  where `types` is a list of type atoms (see the Types guide) and `columns` is a
  list of maps with `:name`, `:type`, and `:nullable?` keys — the same shape as
  metadata-file entries.

  The Mix task uses `Squirrelix.Postgres.inferrer/1` when `--infer` is passed.
  See the [Configuration guide](configuration.html) for connection options.
  """

  @callback infer(Squirrelix.Query.t()) :: {:ok, keyword()} | {:error, struct()}
end

defmodule Squirrelix.Inference do
  @moduledoc false

  alias Squirrelix.Error
  alias Squirrelix.Query
  alias Squirrelix.QueryDirectory
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypedQueryDirectory

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
    TypedQuery.accumulate(query, metadata, {typed_queries, errors})
  end
end
