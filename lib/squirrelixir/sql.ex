defmodule Squirrelixir.SQL do
  @moduledoc """
  SQL helpers used by query analysis and code generation.
  """

  @identifier ~S/(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_]*)(?:\.(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_]*))?/
  @horizontal_space ~S/[ \t\r]*/

  @left_equality Regex.compile!(
                   "(?<identifier>" <>
                     @identifier <>
                     ")" <> @horizontal_space <> "=" <> @horizontal_space <> "\\$(?<index>\\d+)"
                 )

  @right_equality Regex.compile!(
                    "\\$(?<index>\\d+)" <>
                      @horizontal_space <>
                      "=" <> @horizontal_space <> "(?<identifier>" <> @identifier <> ")"
                  )

  @spec valid_identifier?(String.t()) :: boolean()
  def valid_identifier?(identifier) when is_binary(identifier) do
    String.match?(identifier, ~r/\A[a-z_][A-Za-z0-9_]*\z/)
  end

  @type identifier_reason :: :empty | {:invalid_grapheme, non_neg_integer(), String.t()}

  @spec identifier_error(String.t()) :: identifier_reason() | nil
  def identifier_error(identifier) when is_binary(identifier) do
    cond do
      identifier == "" -> :empty
      valid_identifier?(identifier) -> nil
      true -> identifier_grapheme_error(identifier)
    end
  end

  @spec similar_identifier(String.t()) :: String.t() | nil
  def similar_identifier(identifier) when is_binary(identifier) do
    proposal =
      identifier
      |> snake_identifier()
      |> String.graphemes()
      |> Enum.drop_while(&(&1 == "_" or digit?(&1)))
      |> Enum.filter(&identifier_grapheme?/1)
      |> Enum.join()

    if proposal == "", do: nil, else: proposal
  end

  @spec infer_parameter_names(String.t()) :: %{pos_integer() => String.t()}
  def infer_parameter_names(sql) when is_binary(sql) do
    stripped_sql = strip_comments_and_strings(sql)

    [@left_equality, @right_equality]
    |> Enum.flat_map(&Regex.scan(&1, stripped_sql, capture: :all_names))
    |> Enum.reduce(%{}, fn [identifier, index], names ->
      name = normalize_identifier(identifier)

      if valid_identifier?(name) do
        Map.put_new(names, String.to_integer(index), name)
      else
        names
      end
    end)
  end

  defp normalize_identifier(identifier) do
    case String.split(identifier, ".", parts: 2) do
      [column] -> snake_identifier(column)
      [table, column] -> table_identifier(table, column)
    end
  end

  defp table_identifier(table, column) do
    table = snake_identifier(table)
    column = snake_identifier(column)
    column = String.replace_prefix(column, "#{table}_", "")

    "#{table}_#{column}"
  end

  defp snake_identifier(identifier) do
    identifier
    |> String.trim(~s/"/)
    |> String.replace(~r/""/, ~s/"/)
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.replace(~r/[^A-Za-z0-9_]+/, "_")
    |> String.trim("_")
    |> String.downcase()
  end

  defp identifier_grapheme_error(name) do
    case String.graphemes(name) do
      [] ->
        :empty

      [first | rest] ->
        if first == "_" or lowercase_letter?(first) do
          invalid_grapheme_in_rest(rest, 1, name)
        else
          {:invalid_grapheme, 0, first}
        end
    end
  end

  defp invalid_grapheme_in_rest([], _position, _name), do: {:invalid_grapheme, 0, ""}

  defp invalid_grapheme_in_rest([grapheme | rest], position, name) do
    if identifier_grapheme?(grapheme) do
      invalid_grapheme_in_rest(rest, position + 1, name)
    else
      {:invalid_grapheme, position, grapheme}
    end
  end

  defp identifier_grapheme?(grapheme) do
    grapheme == "_" or lowercase_letter?(grapheme) or digit?(grapheme)
  end

  defp lowercase_letter?(<<char::utf8>>), do: char in ?a..?z
  defp lowercase_letter?(_), do: false

  defp digit?(<<char::utf8>>), do: char in ?0..?9
  defp digit?(_), do: false

  defp strip_comments_and_strings(sql) do
    sql
    |> String.to_charlist()
    |> strip_normal([])
    |> Enum.reverse()
    |> List.to_string()
  end

  defp strip_normal([], acc), do: acc

  defp strip_normal([?-, ?- | rest], acc) do
    strip_line_comment(rest, [?\s, ?\s | acc])
  end

  defp strip_normal([?/, ?* | rest], acc) do
    strip_block_comment(rest, 1, [?\s, ?\s | acc])
  end

  defp strip_normal([?' | rest], acc) do
    strip_single_quoted_string(rest, [?\s | acc])
  end

  defp strip_normal([char | rest], acc) do
    strip_normal(rest, [char | acc])
  end

  defp strip_line_comment([], acc), do: acc

  defp strip_line_comment([?\n | rest], acc) do
    strip_normal(rest, [?\n | acc])
  end

  defp strip_line_comment([_char | rest], acc) do
    strip_line_comment(rest, [?\s | acc])
  end

  defp strip_block_comment([], _depth, acc), do: acc

  defp strip_block_comment([?/, ?* | rest], depth, acc) do
    strip_block_comment(rest, depth + 1, [?\s, ?\s | acc])
  end

  defp strip_block_comment([?*, ?/ | rest], 1, acc) do
    strip_normal(rest, [?\s, ?\s | acc])
  end

  defp strip_block_comment([?*, ?/ | rest], depth, acc) do
    strip_block_comment(rest, depth - 1, [?\s, ?\s | acc])
  end

  defp strip_block_comment([?\n | rest], depth, acc) do
    strip_block_comment(rest, depth, [?\n | acc])
  end

  defp strip_block_comment([_char | rest], depth, acc) do
    strip_block_comment(rest, depth, [?\s | acc])
  end

  defp strip_single_quoted_string([], acc), do: acc

  defp strip_single_quoted_string([?', ?' | rest], acc) do
    strip_single_quoted_string(rest, [?\s, ?\s | acc])
  end

  defp strip_single_quoted_string([?\\, ?' | rest], acc) do
    strip_single_quoted_string(rest, [?\s, ?\s | acc])
  end

  defp strip_single_quoted_string([?' | rest], acc) do
    strip_normal(rest, [?\s | acc])
  end

  defp strip_single_quoted_string([?\n | rest], acc) do
    strip_single_quoted_string(rest, [?\n | acc])
  end

  defp strip_single_quoted_string([_char | rest], acc) do
    strip_single_quoted_string(rest, [?\s | acc])
  end
end
