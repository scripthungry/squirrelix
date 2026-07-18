defmodule Squirrelixir.Query do
  @moduledoc """
  Query file parsing helpers reimplemented from Squirrel.
  """

  @enforce_keys [:file, :starting_line, :name, :comment, :content]
  defstruct [:file, :starting_line, :name, :comment, :content]

  alias Squirrelixir.Error.CannotReadFile
  alias Squirrelixir.Error.QueryFileHasInvalidName

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          name: String.t(),
          comment: [String.t()],
          content: String.t()
        }

  @spec from_file(String.t()) :: {:ok, t()} | {:error, struct()}
  def from_file(file) when is_binary(file) do
    with {:ok, content} <- read_query_file(file),
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

    case value_identifier(file_name) do
      {:ok, name} ->
        {:ok, name}

      {:error, reason} ->
        {:error,
         %QueryFileHasInvalidName{
           file: file,
           reason: reason,
           suggested_name: similar_value_identifier(file_name)
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

  defp value_identifier(name) do
    case String.graphemes(name) do
      [] ->
        {:error, :empty}

      [first | rest] ->
        if first_identifier_grapheme?(first) do
          validate_identifier_rest(rest, 1, name)
        else
          {:error, {:invalid_grapheme, 0, first}}
        end
    end
  end

  defp validate_identifier_rest([], _position, name), do: {:ok, name}

  defp validate_identifier_rest([grapheme | rest], position, name) do
    cond do
      identifier_grapheme?(grapheme) ->
        validate_identifier_rest(rest, position + 1, name)

      grapheme in ["?", "!"] and rest == [] ->
        {:ok, name}

      true ->
        {:error, {:invalid_grapheme, position, grapheme}}
    end
  end

  defp similar_value_identifier(string) do
    proposal =
      string
      |> String.trim()
      |> snake_case()
      |> String.graphemes()
      |> Enum.drop_while(&(&1 == "_" or digit?(&1)))
      |> Enum.filter(&identifier_grapheme?/1)
      |> Enum.join()

    if proposal == "", do: nil, else: proposal
  end

  defp snake_case(string) do
    string
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> String.downcase()
  end

  defp identifier_grapheme?(grapheme) do
    grapheme == "_" or lowercase_letter?(grapheme) or digit?(grapheme)
  end

  defp first_identifier_grapheme?(grapheme) do
    grapheme == "_" or lowercase_letter?(grapheme)
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
