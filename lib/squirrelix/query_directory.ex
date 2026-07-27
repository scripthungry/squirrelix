defmodule Squirrelix.QueryDirectory do
  @moduledoc false

  alias Squirrelix.Query

  @enforce_keys [:directory, :queries, :errors]
  defstruct [:directory, :queries, :errors]

  @type t :: %__MODULE__{
          directory: Path.t(),
          queries: [Query.t()],
          errors: [struct()]
        }

  @spec from_files(Path.t(), [Path.t()]) :: t()
  def from_files(directory, files) when is_binary(directory) and is_list(files) do
    {queries, errors} =
      files
      |> Enum.sort()
      |> Enum.reduce({[], []}, &parse_file/2)

    %__MODULE__{
      directory: directory,
      queries: Enum.reverse(queries),
      errors: Enum.reverse(errors)
    }
  end

  @spec from_discovered_files(%{Path.t() => [Path.t()]}) :: [t()]
  def from_discovered_files(discovered_files) when is_map(discovered_files) do
    discovered_files
    |> Enum.sort_by(fn {directory, _files} -> directory end)
    |> Enum.map(fn {directory, files} -> from_files(directory, files) end)
  end

  defp parse_file(file, {queries, errors}) do
    case Query.from_file(file) do
      {:ok, query} -> {[query | queries], errors}
      {:error, error} -> {queries, [error | errors]}
    end
  end
end
