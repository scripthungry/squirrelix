defmodule Squirrelix.TypedQueryDirectory do
  @moduledoc false

  alias Squirrelix.Error
  alias Squirrelix.Error.MissingQueryMetadata
  alias Squirrelix.QueryDirectory
  alias Squirrelix.TypedQuery

  @enforce_keys [:directory, :queries]
  defstruct [:directory, :queries, errors: []]

  @type t :: %__MODULE__{directory: Path.t(), queries: [TypedQuery.t()], errors: [struct()]}

  @spec from_query_directory(QueryDirectory.t(), %{String.t() => keyword()}) :: t()
  def from_query_directory(%QueryDirectory{} = query_directory, metadata) when is_map(metadata) do
    {typed_queries, errors} =
      query_directory.queries
      |> Enum.reduce({[], query_directory.errors}, fn query, {typed_queries, errors} ->
        convert_query(query, metadata, typed_queries, errors)
      end)

    %__MODULE__{
      directory: query_directory.directory,
      queries: Enum.reverse(typed_queries),
      errors: Enum.map(errors, &Error.normalize/1)
    }
  end

  defp convert_query(query, metadata, typed_queries, errors) do
    case Map.fetch(metadata, query.file) do
      {:ok, query_metadata} ->
        typed_query_from_metadata(query, query_metadata, typed_queries, errors)

      :error ->
        {typed_queries, errors ++ [%MissingQueryMetadata{file: query.file}]}
    end
  end

  defp typed_query_from_metadata(query, query_metadata, typed_queries, errors) do
    TypedQuery.accumulate(query, query_metadata, {typed_queries, errors})
  end
end
