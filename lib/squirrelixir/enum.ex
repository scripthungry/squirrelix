defmodule Squirrelixir.Enum do
  @moduledoc """
  Validates Postgres enum names and variants for Elixir codegen compatibility.
  """

  @type reason ::
          :no_variants
          | {:invalid_name, String.t()}
          | {:invalid_variants, [String.t()]}

  @spec validate(String.t(), [String.t()]) :: :ok | {:error, reason()}
  def validate(raw_name, variants) when is_binary(raw_name) and is_list(variants) do
    case type_identifier(pascal_case(raw_name)) do
      {:ok, _} -> validate_variants(variants)
      {:error, _} -> {:error, {:invalid_name, raw_name}}
    end
  end

  defp validate_variants(variants) do
    {valid?, invalid} =
      Enum.reduce(variants, {[], []}, fn variant, {valid, invalid} ->
        case type_identifier(pascal_case(variant)) do
          {:ok, _} -> {[variant | valid], invalid}
          {:error, _} -> {valid, [variant | invalid]}
        end
      end)

    cond do
      invalid != [] ->
        {:error, {:invalid_variants, Enum.reverse(invalid)}}

      valid? == [] ->
        {:error, :no_variants}

      true ->
        :ok
    end
  end

  defp type_identifier(name) do
    case String.graphemes(name) do
      [] ->
        {:error, :empty}

      [first | rest] ->
        if uppercase_letter?(first) do
          validate_type_identifier_rest(rest, 1)
        else
          {:error, {:invalid_grapheme, 0, first}}
        end
    end
  end

  defp validate_type_identifier_rest([], _position), do: {:ok, :valid}

  defp validate_type_identifier_rest([grapheme | rest], position) do
    if type_identifier_grapheme?(grapheme) do
      validate_type_identifier_rest(rest, position + 1)
    else
      {:error, {:invalid_grapheme, position, grapheme}}
    end
  end

  defp pascal_case(string) do
    string
    |> snake_case()
    |> Macro.camelize()
  end

  defp snake_case(string) do
    string
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.replace(~r/[^A-Za-z0-9]+/, "_")
    |> String.downcase()
  end

  defp type_identifier_grapheme?(grapheme) do
    lowercase_letter?(grapheme) or uppercase_letter?(grapheme) or digit?(grapheme)
  end

  defp uppercase_letter?(<<char::utf8>>), do: char >= ?A and char <= ?Z
  defp uppercase_letter?(_), do: false

  defp lowercase_letter?(<<char::utf8>>), do: char >= ?a and char <= ?z
  defp lowercase_letter?(_), do: false

  defp digit?(<<char::utf8>>), do: char >= ?0 and char <= ?9
  defp digit?(_), do: false
end
