defmodule Squirrelix.SQL do
  @moduledoc false

  @identifier ~S/(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_]*)(?:\.(?:"(?:[^"]|"")*"|[A-Za-z_][A-Za-z0-9_]*))?/
  @horizontal_space ~S/[ \t\r]*/
  # Longer operators first so `<=` / `>=` / `<>` / `!=` are not split into `<` / `>` / `=`.
  @comparison_op ~S/(?:<>|!=|<=|>=|<|>|=)/
  @like_op "(?:not" <> @horizontal_space <> ")?(?:i?like)\\b"

  @left_comparison Regex.compile!(
                     "(?<identifier>" <>
                       @identifier <>
                       ")" <>
                       @horizontal_space <>
                       @comparison_op <>
                       @horizontal_space <>
                       "\\$(?<index>\\d+)"
                   )

  @right_comparison Regex.compile!(
                      "\\$(?<index>\\d+)" <>
                        @horizontal_space <>
                        @comparison_op <>
                        @horizontal_space <>
                        "(?<identifier>" <> @identifier <> ")"
                    )

  @left_like Regex.compile!(
               "(?<identifier>" <>
                 @identifier <>
                 ")" <>
                 @horizontal_space <>
                 @like_op <>
                 @horizontal_space <>
                 "\\$(?<index>\\d+)",
               "i"
             )

  @insert_into Regex.compile!(
                 ~S/(?i)\binsert\s+into\s+(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*(?:\s*\.\s*(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*))?)\s*\(/
               )

  @set_list Regex.compile!(~S/(?i)\bset\s*\(/)

  @placeholder_value ~r/\A\$(\d+)\z/

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

    stripped_sql
    |> comparison_parameter_names()
    |> merge_insert_parameter_names(stripped_sql)
    |> merge_set_list_parameter_names(stripped_sql)
  end

  @doc """
  Returns true when `sql` contains a single statement (ignoring comments/strings).

  A trailing semicolon is allowed. Additional `;` separators are rejected so
  callers can safely wrap the SQL in `EXPLAIN` over the simple query protocol.
  """
  @spec single_statement?(String.t()) :: boolean()
  def single_statement?(sql) when is_binary(sql) do
    sql
    |> strip_comments_and_strings()
    |> String.trim()
    |> String.trim_trailing(";")
    |> String.trim()
    |> then(&(not String.contains?(&1, ";")))
  end

  defp comparison_parameter_names(stripped_sql) do
    [@left_comparison, @right_comparison, @left_like]
    |> Enum.flat_map(&Regex.scan(&1, stripped_sql, capture: :all_names))
    |> Enum.reduce(%{}, fn [identifier, index], names ->
      put_inferred_name(names, String.to_integer(index), identifier)
    end)
  end

  defp merge_insert_parameter_names(names, stripped_sql) do
    Enum.reduce(insert_parameter_names(stripped_sql), names, fn {index, name}, acc ->
      Map.put_new(acc, index, name)
    end)
  end

  defp merge_set_list_parameter_names(names, stripped_sql) do
    Enum.reduce(set_list_parameter_names(stripped_sql), names, fn {index, name}, acc ->
      Map.put_new(acc, index, name)
    end)
  end

  defp insert_parameter_names(stripped_sql) do
    @insert_into
    |> Regex.scan(stripped_sql, return: :index)
    |> Enum.flat_map(fn [{start, length}] ->
      after_open = start + length

      columns_and_rest =
        binary_part(stripped_sql, after_open, byte_size(stripped_sql) - after_open)

      case extract_insert_pairs(columns_and_rest) do
        {:ok, pairs} -> pairs
        :error -> []
      end
    end)
  end

  defp set_list_parameter_names(stripped_sql) do
    @set_list
    |> Regex.scan(stripped_sql, return: :index)
    |> Enum.flat_map(fn [{start, length}] ->
      after_open = start + length

      columns_and_rest =
        binary_part(stripped_sql, after_open, byte_size(stripped_sql) - after_open)

      case extract_set_list_pairs(columns_and_rest) do
        {:ok, pairs} -> pairs
        :error -> []
      end
    end)
  end

  defp extract_insert_pairs(sql_after_open_paren) do
    with {:ok, columns_sql, after_columns} <- take_balanced_group(sql_after_open_paren),
         {:ok, after_values} <- expect_values_keyword(after_columns),
         {:ok, value_groups} <- take_value_groups(after_values) do
      columns = parse_sql_list(columns_sql)

      pairs =
        value_groups
        |> Enum.flat_map(&pair_columns_with_placeholders(columns, &1))
        |> Enum.flat_map(&normalized_column_pair/1)

      {:ok, pairs}
    end
  end

  defp extract_set_list_pairs(sql_after_open_paren) do
    with {:ok, columns_sql, after_columns} <- take_balanced_group(sql_after_open_paren),
         {:ok, after_eq} <- expect_equals(after_columns),
         {:ok, values_sql, _rest} <- take_set_list_values(after_eq) do
      columns = parse_sql_list(columns_sql)

      pairs =
        columns
        |> pair_columns_with_placeholders(values_sql)
        |> Enum.flat_map(&normalized_column_pair/1)

      {:ok, pairs}
    end
  end

  defp expect_values_keyword(sql) do
    case Regex.run(~r/\A\s*values\b/i, sql) do
      [matched] ->
        {:ok, binary_part(sql, byte_size(matched), byte_size(sql) - byte_size(matched))}

      nil ->
        :error
    end
  end

  defp expect_equals(sql) do
    case Regex.run(~r/\A\s*=/, sql) do
      [matched] ->
        {:ok, binary_part(sql, byte_size(matched), byte_size(sql) - byte_size(matched))}

      nil ->
        :error
    end
  end

  defp take_set_list_values(sql) do
    case Regex.run(~r/\A\s*row\b/i, sql) do
      [matched] ->
        rest = binary_part(sql, byte_size(matched), byte_size(sql) - byte_size(matched))
        take_paren_group(rest)

      nil ->
        take_paren_group(sql)
    end
  end

  defp take_value_groups(sql) do
    case take_paren_group(sql) do
      {:ok, first, rest} -> collect_value_groups(rest, [first])
      :error -> :error
    end
  end

  defp collect_value_groups(sql, groups) do
    case Regex.run(~r/\A\s*,/, sql) do
      [matched] ->
        rest = binary_part(sql, byte_size(matched), byte_size(sql) - byte_size(matched))

        case take_paren_group(rest) do
          {:ok, group, rest_after} -> collect_value_groups(rest_after, [group | groups])
          :error -> {:ok, Enum.reverse(groups)}
        end

      nil ->
        {:ok, Enum.reverse(groups)}
    end
  end

  defp take_paren_group(sql) do
    case Regex.run(~r/\A\s*\(/, sql) do
      [matched] ->
        rest = binary_part(sql, byte_size(matched), byte_size(sql) - byte_size(matched))
        take_balanced_group(rest)

      nil ->
        :error
    end
  end

  defp take_balanced_group(sql) do
    sql
    |> String.to_charlist()
    |> take_until_matching_paren(1, [])
  end

  defp take_until_matching_paren([], _depth, _acc), do: :error

  defp take_until_matching_paren([?( | rest], depth, acc) do
    take_until_matching_paren(rest, depth + 1, [?( | acc])
  end

  defp take_until_matching_paren([?) | rest], 1, acc) do
    {:ok, acc |> Enum.reverse() |> List.to_string(), List.to_string(rest)}
  end

  defp take_until_matching_paren([?) | rest], depth, acc) do
    take_until_matching_paren(rest, depth - 1, [?) | acc])
  end

  defp take_until_matching_paren([?" | rest], depth, acc) do
    case take_quoted_identifier(rest, [?" | acc]) do
      {:ok, quoted_acc, rest} -> take_until_matching_paren(rest, depth, quoted_acc)
      :error -> :error
    end
  end

  defp take_until_matching_paren([char | rest], depth, acc) do
    take_until_matching_paren(rest, depth, [char | acc])
  end

  defp take_quoted_identifier([], _acc), do: :error

  defp take_quoted_identifier([?", ?" | rest], acc) do
    take_quoted_identifier(rest, [?", ?" | acc])
  end

  defp take_quoted_identifier([?" | rest], acc) do
    {:ok, [?" | acc], rest}
  end

  defp take_quoted_identifier([char | rest], acc) do
    take_quoted_identifier(rest, [char | acc])
  end

  defp parse_sql_list(list_sql) do
    list_sql
    |> split_sql_list()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp pair_columns_with_placeholders(columns, values_sql) do
    values = parse_sql_list(values_sql)

    columns
    |> Enum.zip(values)
    |> Enum.flat_map(fn {column, value} ->
      case Regex.run(@placeholder_value, value) do
        [_, index] -> [{String.to_integer(index), column}]
        nil -> []
      end
    end)
  end

  defp normalized_column_pair({index, identifier}) do
    name = normalize_identifier(identifier)
    if valid_identifier?(name), do: [{index, name}], else: []
  end

  defp put_inferred_name(names, index, identifier) do
    name = normalize_identifier(identifier)

    if valid_identifier?(name) do
      Map.put_new(names, index, name)
    else
      names
    end
  end

  defp split_sql_list(list) do
    list
    |> String.to_charlist()
    |> split_sql_list_chars(0, false, [], [])
    |> Enum.reverse()
    |> Enum.map(&List.to_string/1)
  end

  defp split_sql_list_chars([], _depth, _in_quote, current, parts) do
    [Enum.reverse(current) | parts]
  end

  defp split_sql_list_chars([?" | rest], depth, false, current, parts) do
    split_sql_list_chars(rest, depth, true, [?" | current], parts)
  end

  defp split_sql_list_chars([?", ?" | rest], depth, true, current, parts) do
    split_sql_list_chars(rest, depth, true, [?", ?" | current], parts)
  end

  defp split_sql_list_chars([?" | rest], depth, true, current, parts) do
    split_sql_list_chars(rest, depth, false, [?" | current], parts)
  end

  defp split_sql_list_chars([char | rest], depth, true, current, parts) do
    split_sql_list_chars(rest, depth, true, [char | current], parts)
  end

  defp split_sql_list_chars([?( | rest], depth, false, current, parts) do
    split_sql_list_chars(rest, depth + 1, false, [?( | current], parts)
  end

  defp split_sql_list_chars([?) | rest], depth, false, current, parts) when depth > 0 do
    split_sql_list_chars(rest, depth - 1, false, [?) | current], parts)
  end

  defp split_sql_list_chars([?, | rest], 0, false, current, parts) do
    split_sql_list_chars(rest, 0, false, [], [Enum.reverse(current) | parts])
  end

  defp split_sql_list_chars([char | rest], depth, false, current, parts) do
    split_sql_list_chars(rest, depth, false, [char | current], parts)
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
