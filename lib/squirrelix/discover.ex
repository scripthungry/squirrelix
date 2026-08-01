defmodule Squirrelix.Discover do
  @moduledoc false

  # SQL directory discovery under conventional project roots.
  # Kept separate from `Squirrelix.CLI` (connection option parsing) so internals
  # have a single clear owner for each concern.

  alias Squirrelix.Error.CannotReadFile
  alias Squirrelix.Project
  alias Squirrelix.QueryDirectory

  @type discovered_sql_files :: %{Path.t() => [Path.t()]}

  @doc """
  Recursively finds `sql/` directories and their `.sql` files under `path`.

  Returns `{:ok, map}` of directory paths to sorted SQL file paths, or
  `{:error, %CannotReadFile{}}` when a directory cannot be listed.
  """
  @spec discover_sql_directories(Path.t()) ::
          {:ok, discovered_sql_files()} | {:error, CannotReadFile.t()}
  def discover_sql_directories(path) when is_binary(path) do
    do_discover_sql_directories(path)
  end

  @spec query_files(Path.t()) :: {:ok, discovered_sql_files()} | {:error, CannotReadFile.t()}
  def query_files(root) when is_binary(root) do
    root
    |> Project.source_roots()
    |> Enum.reduce_while({:ok, %{}}, fn source_root, {:ok, acc} ->
      case discover_sql_directories(source_root) do
        {:ok, found} -> {:cont, {:ok, Map.merge(acc, found)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @spec query_directories(Path.t()) ::
          {:ok, [QueryDirectory.t()]} | {:error, CannotReadFile.t()}
  def query_directories(root) when is_binary(root) do
    case query_files(root) do
      {:ok, files} -> {:ok, QueryDirectory.from_discovered_files(files)}
      {:error, _} = error -> error
    end
  end

  @spec directory_to_output_file(String.t()) :: String.t()
  def directory_to_output_file(directory) when is_binary(directory) do
    directory
    |> Path.dirname()
    |> Path.join("sql.ex")
  end

  defp do_discover_sql_directories(path) do
    case Path.basename(path) do
      "sql" -> list_sql_files(path)
      _ -> discover_nested_sql_directories(path)
    end
  end

  defp list_sql_files(path) do
    case File.ls(path) do
      {:ok, entries} ->
        files =
          entries
          |> Enum.map(&Path.join(path, &1))
          |> Enum.filter(&(File.regular?(&1) and Path.extname(&1) == ".sql"))
          |> Enum.sort()

        {:ok, %{path => files}}

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, %CannotReadFile{file: path, reason: reason}}
    end
  end

  defp discover_nested_sql_directories(path) do
    with {:ok, directories} <- list_child_directories(path) do
      merge_discovered_directories(directories)
    end
  end

  defp merge_discovered_directories(directories) do
    Enum.reduce_while(directories, {:ok, %{}}, fn directory, {:ok, acc} ->
      case do_discover_sql_directories(directory) do
        {:ok, found} -> {:cont, {:ok, Map.merge(acc, found)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Child filesystem directories only — not SQL discovery. Kept private and named
  # distinctly from `discover_sql_directories/1` to avoid the old CLI ambiguity.
  defp list_child_directories(path) do
    case File.ls(path) do
      {:ok, entries} ->
        directories =
          entries
          |> Enum.map(&Path.join(path, &1))
          |> Enum.filter(&File.dir?/1)

        {:ok, directories}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, %CannotReadFile{file: path, reason: reason}}
    end
  end
end
