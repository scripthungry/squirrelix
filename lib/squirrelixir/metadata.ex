defmodule Squirrelixir.Metadata do
  @moduledoc """
  Loads Elixir query metadata files for the current code generation pipeline.
  """

  alias Squirrelixir.Error.CannotReadFile
  alias Squirrelixir.Error.InvalidQueryMetadataFile

  @spec from_file(Path.t(), keyword()) ::
          {:ok, %{String.t() => keyword()}}
          | {:error, CannotReadFile.t() | InvalidQueryMetadataFile.t()}
  def from_file(file, opts \\ []) when is_binary(file) and is_list(opts) do
    root = Keyword.fetch!(opts, :root)

    with {:ok, content} <- read_metadata_file(file),
         {:ok, metadata} <- evaluate_metadata_file(file, content) do
      {:ok, expand_query_paths(metadata, root)}
    end
  end

  defp read_metadata_file(file) do
    case File.read(file) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, %CannotReadFile{file: file, reason: reason}}
    end
  end

  defp evaluate_metadata_file(file, content) do
    case Code.eval_string(content, [], file: file) do
      {metadata, _binding} when is_map(metadata) -> {:ok, metadata}
      {_metadata, _binding} -> {:error, %InvalidQueryMetadataFile{file: file, reason: :not_a_map}}
    end
  rescue
    error -> {:error, %InvalidQueryMetadataFile{file: file, reason: error}}
  end

  defp expand_query_paths(metadata, root) do
    Map.new(metadata, fn {query_file, query_metadata} ->
      {expand_query_path(query_file, root), query_metadata}
    end)
  end

  defp expand_query_path(query_file, root) when is_binary(query_file) do
    if Path.type(query_file) == :absolute do
      query_file
    else
      Path.expand(query_file, root)
    end
  end
end
