defmodule Squirrelixir.Output do
  @moduledoc """
  Safe output-file writing for generated code.
  """

  alias Squirrelixir.Error.CannotOverwriteFile
  alias Squirrelixir.Error.CannotReadFile
  alias Squirrelixir.Error.CannotWriteFile
  alias Squirrelixir.Error.OutdatedFile

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
        case Squirrelixir.compare_code_snippets(actual_content, expected_content) do
          :same -> :ok
          :different -> {:error, %OutdatedFile{file: file}}
        end

      {:error, reason} ->
        {:error, %CannotReadFile{file: file, reason: reason}}
    end
  end

  defp existing_file_origin(file) do
    case File.read(file) do
      {:ok, content} -> {:ok, Squirrelixir.classify_file_content(content)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_file(file, content) do
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
end
