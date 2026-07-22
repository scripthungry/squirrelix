defmodule SquirrElix.Output do
  @moduledoc """
  Safe output-file writing for generated code.
  """

  alias SquirrElix.Error.CannotOverwriteFile
  alias SquirrElix.Error.CannotReadFile
  alias SquirrElix.Error.CannotWriteFile
  alias SquirrElix.Error.OutdatedFile

  @spec safe_write(Path.t(), String.t()) ::
          :ok | {:error, CannotOverwriteFile.t() | CannotWriteFile.t()}
  def safe_write(file, content) when is_binary(file) and is_binary(content) do
    case existing_file_origin(file) do
      {:ok, :not_generated} ->
        {:error, %CannotOverwriteFile{file: file}}

      {:ok, :likely_generated} ->
        write_file(file, content)

      {:ok, :empty} ->
        write_file(file, content)

      {:error, :enoent} ->
        write_file(file, content)

      {:error, reason} ->
        {:error, %CannotWriteFile{file: file, reason: reason}}
    end
  end

  @spec check_file(Path.t(), String.t()) :: :ok | {:error, CannotReadFile.t() | OutdatedFile.t()}
  def check_file(file, expected_content) when is_binary(file) and is_binary(expected_content) do
    case File.read(file) do
      {:ok, actual_content} ->
        case SquirrElix.compare_code_snippets(actual_content, expected_content) do
          :same -> :ok
          :different -> {:error, %OutdatedFile{file: file}}
        end

      {:error, reason} ->
        {:error, %CannotReadFile{file: file, reason: reason}}
    end
  end

  defp existing_file_origin(file) do
    case File.read(file) do
      {:ok, content} -> {:ok, SquirrElix.classify_file_content(content)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_file(file, content) do
    content = format_content(file, content)

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

  defp format_content(file, content) do
    if Path.extname(file) in [".ex", ".exs"] do
      content
      |> Code.format_string!()
      |> IO.iodata_to_binary()
      |> Kernel.<>("\n")
    else
      content
    end
  rescue
    _ -> content
  end
end
