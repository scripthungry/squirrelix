defmodule Squirrelix.Metadata do
  @moduledoc """
  Loads and writes Elixir query metadata files for the current code generation pipeline.

  Metadata files are evaluated with `Code.eval_string/3` and must return a map.
  Treat them like `mix.exs` / `config/*.exs`: only load trusted, project-local
  files. Prefer `--infer` in CI when you do not want to maintain evaluated Elixir
  metadata.

  Use `to_file/3` (or Mix `--infer --write-metadata PATH`) to capture inferred
  types for offline `mix squirrelix.check` / `gen` without Postgres.
  """

  alias Squirrelix.Column
  alias Squirrelix.Error.CannotReadFile
  alias Squirrelix.Error.CannotWriteFile
  alias Squirrelix.Error.InvalidQueryMetadataFile
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypedQueryDirectory

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

  @doc """
  Builds a metadata map (absolute query paths) from typed query directories.

  The result is suitable for `Squirrelix.generate/3` / `check/3` and for
  `to_file/3`.
  """
  @spec from_typed_directories([TypedQueryDirectory.t()]) :: %{Path.t() => keyword()}
  def from_typed_directories(directories) when is_list(directories) do
    directories
    |> Enum.flat_map(& &1.queries)
    |> Map.new(fn %TypedQuery{} = query ->
      {Path.expand(query.file),
       [
         params: Enum.map(query.params, & &1.type),
         returns: Enum.map(query.returns, &column_to_map/1)
       ]}
    end)
  end

  @doc """
  Writes a metadata map as evaluated Elixir to `file`.

  Query paths are written relative to `:root` when possible. Parent directories
  are created as needed. Overwrites any existing file at `file`.
  """
  @spec to_file(Path.t(), %{Path.t() => keyword()}, keyword()) ::
          :ok | {:error, CannotWriteFile.t()}
  def to_file(file, metadata, opts \\ [])
      when is_binary(file) and is_map(metadata) and is_list(opts) do
    root = Keyword.fetch!(opts, :root)
    content = dump(metadata, root)

    file
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok ->
        case File.write(file, content) do
          :ok -> :ok
          {:error, reason} -> {:error, %CannotWriteFile{file: file, reason: reason}}
        end

      {:error, reason} ->
        {:error, %CannotWriteFile{file: file, reason: reason}}
    end
  end

  @doc """
  Serializes a metadata map to formatted Elixir source with relative query paths.
  """
  @spec dump(%{Path.t() => keyword()}, Path.t()) :: String.t()
  def dump(metadata, root) when is_map(metadata) and is_binary(root) do
    metadata
    |> Map.new(fn {query_file, query_metadata} ->
      {relativize_query_path(query_file, root), serialize_entry(query_metadata)}
    end)
    |> inspect(pretty: true, limit: :infinity, width: 98)
    |> format_elixir()
  end

  defp column_to_map(%Column{} = column) do
    %{name: column.name, type: column.type, nullable?: column.nullable?}
  end

  defp serialize_entry(query_metadata) when is_list(query_metadata) do
    params = Keyword.fetch!(query_metadata, :params)
    returns = Keyword.fetch!(query_metadata, :returns)

    [
      params: params,
      returns: Enum.map(returns, &serialize_return/1)
    ]
  end

  defp serialize_return(%Column{} = column), do: column_to_map(column)

  defp serialize_return(%{name: name, type: type, nullable?: nullable?}) do
    %{name: name, type: type, nullable?: nullable?}
  end

  defp relativize_query_path(query_file, root) do
    absolute = Path.expand(query_file)
    root = Path.expand(root)
    relative = Path.relative_to(absolute, root)

    if relative == absolute do
      absolute
    else
      relative
    end
  end

  defp format_elixir(source) do
    source
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  rescue
    _ -> source <> "\n"
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
