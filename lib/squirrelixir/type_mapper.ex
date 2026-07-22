defmodule Squirrelixir.TypeMapper do
  @moduledoc """
  Maps Postgres type names into Squirrelixir's Elixir type metadata.
  """

  alias Squirrelixir.Error.UnsupportedPostgresType

  @base_types %{
    "bool" => :boolean,
    "text" => :string,
    "char" => :string,
    "bpchar" => :string,
    "varchar" => :string,
    "citext" => :string,
    "name" => :string,
    "float4" => :float,
    "float8" => :float,
    "numeric" => :decimal,
    "int2" => :integer,
    "int4" => :integer,
    "int8" => :integer,
    "json" => :map,
    "jsonb" => :map,
    "uuid" => :uuid,
    "bytea" => :binary,
    "date" => :date,
    "time" => :time,
    "timestamp" => :naive_datetime,
    "timestamptz" => :utc_datetime
  }

  @type_hints %{
    "timestamptz" =>
      "In Postgres a timestamptz is converted to a regular timestamp using the connection's " <>
        "time zone. This is very error prone and should be avoided in favour of using regular timestamps."
  }

  @elixir_types MapSet.new([
                  :boolean,
                  :string,
                  :float,
                  :decimal,
                  :integer,
                  :map,
                  :uuid,
                  :binary,
                  :date,
                  :time,
                  :naive_datetime,
                  :utc_datetime
                ])

  @type elixir_type :: atom() | {:list, elixir_type()}

  @spec hint_for(String.t()) :: String.t() | nil
  def hint_for(name) when is_binary(name), do: Map.get(@type_hints, name)

  @spec from_postgres(String.t(), keyword()) ::
          {:ok, elixir_type()} | {:error, UnsupportedPostgresType.t()}
  def from_postgres(name, opts \\ []) when is_binary(name) and is_list(opts) do
    array_dimensions = Keyword.get(opts, :array_dimensions, 0)

    with {:ok, type} <- base_type(name, Keyword.get(opts, :kind), Keyword.get(opts, :base)) do
      {:ok, wrap_lists(type, array_dimensions)}
    end
  end

  defp base_type(_name, "e", _base), do: {:ok, :string}

  defp base_type(_name, "d", base) when is_binary(base) do
    base_type(base, nil, nil)
  end

  defp base_type(name, _kind, _base) do
    case Map.fetch(@base_types, name) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, unsupported_type(name)}
    end
  end

  defp unsupported_type(name) do
    %UnsupportedPostgresType{name: name, hint: hint_for(name)}
  end

  @spec normalize_type(term()) :: {:ok, elixir_type()} | {:error, UnsupportedPostgresType.t()}
  def normalize_type({:list, type}) do
    with {:ok, type} <- normalize_type(type) do
      {:ok, {:list, type}}
    end
  end

  def normalize_type(type) when is_atom(type) do
    if MapSet.member?(@elixir_types, type) do
      {:ok, type}
    else
      {:error, %UnsupportedPostgresType{name: Atom.to_string(type), hint: nil}}
    end
  end

  def normalize_type({:postgres, name}) when is_binary(name) do
    from_postgres(name)
  end

  def normalize_type(%{postgres: name} = descriptor) when is_binary(name) do
    from_postgres(name,
      array_dimensions: Map.get(descriptor, :array_dimensions, 0),
      kind: Map.get(descriptor, :kind),
      base: Map.get(descriptor, :base)
    )
  end

  defp wrap_lists(type, 0), do: type
  defp wrap_lists(type, count), do: wrap_lists({:list, type}, count - 1)

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
