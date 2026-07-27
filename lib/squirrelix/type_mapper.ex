defmodule Squirrelix.TypeMapper do
  @moduledoc """
  Maps Postgres type names into Squirrelix's Elixir type metadata and typespecs.

  ## Postgres enums

  Custom Postgres enums (`kind: "e"`) map to the internal atom `:string` and emit
  `String.t()` in generated `@spec`s. Runtime encode/decode passes enum labels
  through as plain strings — Squirrelix does not generate Gleam-style enum ADTs.

  ## JSON and JSONB

  JSON columns map to the internal atom `:map` (shared by `json` and `jsonb`) but
  emit `term()` in generated `@spec`s. JSON values are not always objects, and
  Postgrex may return maps, lists, or primitives depending on the stored payload.
  `term()` matches Elixir 1.20 practice for dynamically typed JSON columns; row
  result maps still use `map()` with `required/1` keys via `row_typespec/1`.

  ## Composite types

  Postgres composite types (`kind: "c"`, including `create type ... as (...)`)
  are **intentionally unsupported**. Squirrelix rejects them with an
  `UnsupportedPostgresType` error and an actionable hint (select individual
  fields, or cast to `json`/`jsonb`/`text`). This matches Gleam Squirrel and
  keeps generated Elixir APIs limited to stdlib typespecs and flat row maps —
  no nested composite modules or opaque encodings.
  """

  alias Squirrelix.Error.UnsupportedPostgresType

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

  @composite_hint "Postgres composite types are not supported. Select individual fields " <>
                    "(for example `(value).field`), or cast to `json`/`jsonb`/`text` in the query."

  @point_hint "Postgres geometric types such as `point` are not supported. Prefer separate " <>
                "numeric columns, or cast to `text`/`json` if you only need a string representation."

  @type_hints %{
    "timestamptz" =>
      "In Postgres a timestamptz is converted to a regular timestamp using the connection's " <>
        "time zone. This is very error prone and should be avoided in favour of using regular timestamps.",
    "point" => @point_hint
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

  @spec validate_enum(String.t(), [String.t()]) :: :ok | {:error, :no_variants}
  def validate_enum(_name, []), do: {:error, :no_variants}
  def validate_enum(_name, [_ | _]), do: :ok

  @spec from_postgres(String.t(), keyword()) ::
          {:ok, elixir_type()} | {:error, UnsupportedPostgresType.t()}
  def from_postgres(name, opts \\ []) when is_binary(name) and is_list(opts) do
    array_dimensions = Keyword.get(opts, :array_dimensions, 0)

    with {:ok, type} <- base_type(name, Keyword.get(opts, :kind), Keyword.get(opts, :base)) do
      {:ok, wrap_lists(type, array_dimensions)}
    end
  end

  @spec typespec(elixir_type()) :: String.t()
  def typespec(:integer), do: "integer()"
  def typespec(:string), do: "String.t()"
  def typespec(:boolean), do: "boolean()"
  def typespec(:float), do: "float()"
  def typespec(:decimal), do: "Decimal.t()"
  def typespec(:binary), do: "binary()"
  def typespec(:map), do: "term()"
  def typespec(:uuid), do: "String.t()"
  def typespec(:date), do: "Date.t()"
  def typespec(:time), do: "Time.t()"
  def typespec(:naive_datetime), do: "NaiveDateTime.t()"
  def typespec(:utc_datetime), do: "DateTime.t()"
  def typespec({:list, type}), do: "[#{typespec(type)}]"
  def typespec(_type), do: "term()"

  @spec column_typespec(atom(), elixir_type(), boolean()) :: String.t()
  def column_typespec(name, type, nullable?) do
    spec = if nullable?, do: "#{typespec(type)} | nil", else: typespec(type)
    "required(#{inspect(name)}) => #{spec}"
  end

  @spec row_typespec([{atom(), elixir_type(), boolean()}]) :: String.t()
  def row_typespec(columns) when is_list(columns) do
    columns
    |> Enum.map_join(", ", fn {name, type, nullable?} ->
      column_typespec(name, type, nullable?)
    end)
    |> then(&"%{#{&1}}")
  end

  @spec return_typespec([] | [{atom(), elixir_type(), boolean()}]) :: String.t()
  def return_typespec([]), do: ":ok"

  def return_typespec(columns) when is_list(columns) do
    "[#{row_typespec(columns)}]"
  end

  defp base_type(_name, "e", _base), do: {:ok, :string}

  defp base_type(_name, "d", base) when is_binary(base) do
    base_type(base, nil, nil)
  end

  defp base_type(name, "c", _base) do
    {:error, unsupported_composite(name)}
  end

  defp base_type(name, _kind, _base) do
    case Map.fetch(@base_types, name) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, unsupported_type(name)}
    end
  end

  defp unsupported_composite(name) do
    %UnsupportedPostgresType{name: name, hint: @composite_hint}
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
end
