defmodule Squirrelixir.Inference.Describer do
  @moduledoc """
  Behaviour for modules that describe SQL query parameters and returned columns.
  """

  @callback describe(Squirrelixir.Query.t()) :: {:ok, keyword()} | {:error, struct()}
end

defmodule Squirrelixir.Inference do
  @moduledoc """
  Converts parsed query directories into typed query directories using a describer.
  """

  alias Squirrelixir.Error
  alias Squirrelixir.Query
  alias Squirrelixir.QueryDirectory
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

  @type describer :: (Query.t() -> {:ok, keyword()} | {:error, struct()}) | module()

  @spec from_query_directories([QueryDirectory.t()], describer()) :: [TypedQueryDirectory.t()]
  def from_query_directories(query_directories, describer) when is_list(query_directories) do
    query_directories
    |> Enum.sort_by(& &1.directory)
    |> Enum.map(&from_query_directory(&1, describer))
  end

  defp from_query_directory(%QueryDirectory{} = query_directory, describer) do
    {typed_queries, errors} =
      Enum.reduce(query_directory.queries, {[], query_directory.errors}, fn query, acc ->
        describe_query(query, describer, acc)
      end)

    %TypedQueryDirectory{
      directory: query_directory.directory,
      queries: Enum.reverse(typed_queries),
      errors: Enum.map(errors, &Error.normalize/1)
    }
  end

  defp describe_query(query, describer, {typed_queries, errors}) do
    case call_describer(describer, query) do
      {:ok, metadata} ->
        typed_query_from_metadata(query, metadata, typed_queries, errors)

      {:error, error} ->
        {typed_queries, errors ++ [error |> Error.attach_query(query) |> Error.normalize()]}
    end
  end

  defp call_describer(describer, query) when is_function(describer, 1) do
    describer.(query)
  end

  defp call_describer(describer, query) when is_atom(describer) do
    describer.describe(query)
  end

  defp typed_query_from_metadata(query, metadata, typed_queries, errors) do
    case TypedQuery.from_query(query, metadata) do
      {:ok, typed_query} -> {[typed_query | typed_queries], errors}
      {:error, error} -> {typed_queries, errors ++ [Error.attach_query(error, query)]}
    end
  end
end
