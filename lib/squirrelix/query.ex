defmodule Squirrelix.Query do
  @moduledoc """
  A parsed SQL query file.

  Part of the supported public API **only** as the argument to
  `Squirrelix.Inference.Inferrer` callbacks (and to functions returned by
  `Squirrelix.Postgres.inferrer/1`). Fields are plain struct keys:

    * `:file` — absolute path to the `.sql` file
    * `:starting_line` — 1-based start of the query body
    * `:name` — Elixir function name derived from the file basename
    * `:comment` — leading `--` comment lines (become `@doc`)
    * `:content` — full file contents

  Parsing helpers on this module are internal and may change without notice.
  Prefer `Squirrelix.generate/3` / Mix tasks for normal use.
  """

  @enforce_keys [:file, :starting_line, :name, :comment, :content]
  defstruct [:file, :starting_line, :name, :comment, :content]

  alias Squirrelix.Error.CannotReadFile
  alias Squirrelix.Error.QueryFileHasInvalidName
  alias Squirrelix.Error.QueryHasMultipleStatements
  alias Squirrelix.SQL

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          name: String.t(),
          comment: [String.t()],
          content: String.t()
        }

  @doc false
  @spec from_file(String.t()) ::
          {:ok, t()}
          | {:error,
             CannotReadFile.t() | QueryFileHasInvalidName.t() | QueryHasMultipleStatements.t()}
  def from_file(file) when is_binary(file) do
    with {:ok, content} <- read_query_file(file),
         :ok <- ensure_single_statement(file, content),
         {:ok, name} <- query_name(file) do
      {:ok,
       %__MODULE__{
         file: file,
         starting_line: 1,
         name: name,
         comment: take_comment(content),
         content: content
       }}
    end
  end

  defp ensure_single_statement(file, content) do
    if SQL.single_statement?(content) do
      :ok
    else
      {:error,
       %QueryHasMultipleStatements{
         file: file,
         starting_line: 1,
         content: content
       }}
    end
  end

  defp read_query_file(file) do
    case File.read(file) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, %CannotReadFile{file: file, reason: reason}}
    end
  end

  defp query_name(file) do
    file_name =
      file
      |> Path.basename()
      |> Path.rootname()

    case parse_query_name(file_name) do
      {:ok, name} ->
        {:ok, name}

      {:error, reason} ->
        {:error,
         %QueryFileHasInvalidName{
           file: file,
           reason: reason,
           suggested_name: SQL.similar_identifier(file_name)
         }}
    end
  end

  defp take_comment(query) do
    do_take_comment(query, [])
  end

  defp do_take_comment(query, lines) do
    trimmed_query = String.trim_leading(query)

    if String.starts_with?(trimmed_query, "--") do
      trimmed_query
      |> String.trim_leading("--")
      |> split_comment_line()
      |> case do
        {line, rest} -> do_take_comment(rest, [String.trim(line) | lines])
        line -> do_take_comment("", [String.trim(line) | lines])
      end
    else
      Enum.reverse(lines)
    end
  end

  defp split_comment_line(comment) do
    case String.split(comment, "\n", parts: 2) do
      [line, rest] -> {line, rest}
      [line] -> line
    end
  end

  defp parse_query_name(name) do
    case String.graphemes(name) do
      [] ->
        {:error, :empty}

      [first | rest] ->
        if first == "_" or lowercase_letter?(first) do
          validate_query_name_rest(rest, 1, name)
        else
          {:error, {:invalid_grapheme, 0, first}}
        end
    end
  end

  defp validate_query_name_rest([], _position, name), do: {:ok, name}

  defp validate_query_name_rest([grapheme | rest], position, name) do
    cond do
      identifier_grapheme?(grapheme) ->
        validate_query_name_rest(rest, position + 1, name)

      grapheme in ["?", "!"] and rest == [] ->
        {:ok, name}

      true ->
        {:error, {:invalid_grapheme, position, grapheme}}
    end
  end

  defp identifier_grapheme?(grapheme) do
    grapheme == "_" or lowercase_letter?(grapheme) or digit?(grapheme)
  end

  defp lowercase_letter?(<<char::utf8>>) do
    char >= ?a and char <= ?z
  end

  defp lowercase_letter?(_), do: false

  defp digit?(<<char::utf8>>) do
    char >= ?0 and char <= ?9
  end

  defp digit?(_), do: false
end
