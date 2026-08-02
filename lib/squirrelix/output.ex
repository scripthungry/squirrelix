defmodule Squirrelix.Output do
  @moduledoc false

  alias Squirrelix.Error.CannotOverwriteFile
  alias Squirrelix.Error.CannotReadFile
  alias Squirrelix.Error.CannotWriteFile
  alias Squirrelix.Error.OutdatedFile

  @tmp_suffix ".squirrelix.tmp"
  @bak_suffix ".squirrelix.bak"

  @type prepared_write :: %{file: Path.t(), content: String.t()}

  @spec safe_write(Path.t(), String.t(), keyword()) ::
          :ok | {:error, CannotOverwriteFile.t() | CannotWriteFile.t()}
  def safe_write(file, content, opts \\ [])
      when is_binary(file) and is_binary(content) and is_list(opts) do
    with {:ok, prepared} <- prepare_write(file, content, opts) do
      commit_writes([prepared])
    end
  end

  @doc """
  Prepares a write, optionally formatting Elixir sources.

  Pass `format: false` when `content` is already formatted (e.g. from
  `Squirrelix.Codegen.generate_module/3`) to avoid a second `Code.format_string!/1`.
  """
  @spec prepare_write(Path.t(), String.t(), keyword()) ::
          {:ok, prepared_write()} | {:error, CannotOverwriteFile.t() | CannotWriteFile.t()}
  def prepare_write(file, content, opts \\ [])
      when is_binary(file) and is_binary(content) and is_list(opts) do
    format? = Keyword.get(opts, :format, true)

    case existing_file_origin(file) do
      {:ok, :not_generated} ->
        {:error, %CannotOverwriteFile{file: file}}

      {:ok, origin} when origin in [:likely_generated, :empty] ->
        {:ok, %{file: file, content: maybe_format_content(file, content, format?)}}

      {:error, :enoent} ->
        {:ok, %{file: file, content: maybe_format_content(file, content, format?)}}

      {:error, reason} ->
        {:error, %CannotWriteFile{file: file, reason: reason}}
    end
  end

  @doc """
  Commits prepared writes with temp+rename.

  All temp files are written first. Targets are then replaced via rename, with
  backups restored if any rename fails so earlier files are not left updated.
  """
  @spec commit_writes([prepared_write()]) :: :ok | {:error, CannotWriteFile.t()}
  def commit_writes(prepared) when is_list(prepared) do
    with :ok <- stage_writes(prepared) do
      finalize_writes(prepared)
    end
  end

  # Split for tests that sabotage a staged temp to exercise rename rollback.
  @doc false
  @spec stage_writes([prepared_write()]) :: :ok | {:error, CannotWriteFile.t()}
  def stage_writes(prepared) when is_list(prepared) do
    Enum.reduce_while(prepared, :ok, fn %{file: file, content: content}, :ok ->
      case stage_temp(file, content) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          cleanup_temps(prepared)
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc false
  @spec finalize_writes([prepared_write()]) :: :ok | {:error, CannotWriteFile.t()}
  def finalize_writes(prepared) when is_list(prepared) do
    case do_commit_renames(prepared, []) do
      :ok ->
        cleanup_backups(prepared)
        :ok

      {:error, reason, replaced} ->
        restore_backups(Enum.reverse(replaced), prepared)
        cleanup_temps(prepared)
        cleanup_backups(prepared)
        {:error, reason}
    end
  end

  @spec check_file(Path.t(), String.t()) :: :ok | {:error, CannotReadFile.t() | OutdatedFile.t()}
  def check_file(file, expected_content) when is_binary(file) and is_binary(expected_content) do
    case File.read(file) do
      {:ok, actual_content} ->
        case Squirrelix.compare_code_snippets(actual_content, expected_content) do
          :same -> :ok
          :different -> {:error, %OutdatedFile{file: file}}
        end

      {:error, reason} ->
        {:error, %CannotReadFile{file: file, reason: reason}}
    end
  end

  defp stage_temp(file, content) do
    dir = Path.dirname(file)
    temp = temp_path(file)

    case File.mkdir_p(dir) do
      :ok ->
        case File.write(temp, content) do
          :ok ->
            :ok

          {:error, reason} ->
            File.rm(temp)
            {:error, %CannotWriteFile{file: file, reason: reason}}
        end

      {:error, reason} ->
        {:error, %CannotWriteFile{file: file, reason: reason}}
    end
  end

  defp do_commit_renames([], _replaced), do: :ok

  defp do_commit_renames([%{file: file} | rest], replaced) do
    temp = temp_path(file)
    bak = backup_path(file)

    with :ok <- maybe_backup(file, bak),
         :ok <- rename_temp(temp, file) do
      do_commit_renames(rest, [file | replaced])
    else
      {:error, reason} ->
        {:error, %CannotWriteFile{file: file, reason: reason}, replaced}
    end
  end

  defp maybe_backup(file, bak) do
    if File.exists?(file) do
      _ = File.rm(bak)
      File.rename(file, bak)
    else
      :ok
    end
  end

  defp rename_temp(temp, file) do
    case File.rename(temp, file) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = File.rm(temp)
        {:error, reason}
    end
  end

  # `replaced` is newest-first. Restore each from backup when present; otherwise
  # remove the newly created file. Files not yet replaced still have backups
  # only if we backed them up before failing — those are cleaned via cleanup_backups
  # after restore of the replaced set. For a file we backed up but failed to
  # rename onto, restore it too.
  defp restore_backups(replaced_newest_first, prepared) do
    replaced = MapSet.new(replaced_newest_first)

    Enum.each(prepared, fn %{file: file} ->
      bak = backup_path(file)

      cond do
        MapSet.member?(replaced, file) and File.exists?(bak) ->
          _ = File.rm(file)
          _ = File.rename(bak, file)

        MapSet.member?(replaced, file) ->
          _ = File.rm(file)

        File.exists?(bak) ->
          # Backed up but rename of temp failed — put the original back.
          _ = File.rm(file)
          _ = File.rename(bak, file)

        true ->
          :ok
      end
    end)
  end

  defp cleanup_temps(prepared) do
    Enum.each(prepared, fn %{file: file} -> File.rm(temp_path(file)) end)
  end

  defp cleanup_backups(prepared) do
    Enum.each(prepared, fn %{file: file} -> File.rm(backup_path(file)) end)
  end

  defp temp_path(file), do: file <> @tmp_suffix
  defp backup_path(file), do: file <> @bak_suffix

  defp existing_file_origin(file) do
    case File.read(file) do
      {:ok, content} -> {:ok, Squirrelix.classify_file_content(content)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_format_content(file, content, true), do: format_content(file, content)
  defp maybe_format_content(_file, content, false), do: content

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
    _e in [TokenMissingError, SyntaxError, MismatchedDelimiterError] ->
      content
  end
end
