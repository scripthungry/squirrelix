defmodule Squirrelix.TypeMapper do
  @moduledoc false

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

  @range_hint "Postgres range types are not mapped. Prefer selecting lower/upper " <>
                "bounds as separate columns of a supported type, or cast the range to " <>
                "text/jsonb in SQL."

  @multirange_hint "Postgres multirange types are not mapped. Prefer expanding ranges " <>
                     "into supported scalar columns, or cast to text/jsonb in SQL."

  @geometric_hint "Geometric types are not mapped. Cast to text in SQL, or select " <>
                    "coordinates as separate float/numeric columns."

  @network_hint "Network address types are not mapped. Cast to text in SQL."

  @interval_hint "interval is not mapped. Prefer extracting epoch seconds " <>
                   "(for example `extract(epoch from ...)::float8`) or casting to text in SQL."

  @bit_hint "Bit string types are not mapped. Cast to text in SQL."

  @text_search_hint "Full-text search types are not mapped. Cast to text in SQL, or " <>
                      "return ranking/boolean results as supported scalars."

  @money_hint "money is not mapped. Prefer numeric/decimal columns instead of money."

  @xml_hint "xml is not mapped. Prefer text or jsonb columns instead."

  @oid_hint "OID-family types are not mapped. Cast to text or use a supported " <>
              "scalar that identifies the object."

  @hstore_hint "hstore is not mapped. Prefer jsonb instead of hstore."

  @timetz_hint "timetz is not mapped. Prefer time (without time zone) columns."

  @type_hints %{
    "timestamptz" =>
      "In Postgres a timestamptz is converted to a regular timestamp using the connection's " <>
        "time zone. This is very error prone and should be avoided in favour of using regular timestamps.",
    "int4range" => @range_hint,
    "int8range" => @range_hint,
    "numrange" => @range_hint,
    "tsrange" => @range_hint,
    "tstzrange" => @range_hint,
    "daterange" => @range_hint,
    "int4multirange" => @multirange_hint,
    "int8multirange" => @multirange_hint,
    "nummultirange" => @multirange_hint,
    "tsmultirange" => @multirange_hint,
    "tstzmultirange" => @multirange_hint,
    "datemultirange" => @multirange_hint,
    "point" => @geometric_hint,
    "box" => @geometric_hint,
    "circle" => @geometric_hint,
    "line" => @geometric_hint,
    "lseg" => @geometric_hint,
    "path" => @geometric_hint,
    "polygon" => @geometric_hint,
    "inet" => @network_hint,
    "cidr" => @network_hint,
    "macaddr" => @network_hint,
    "macaddr8" => @network_hint,
    "interval" => @interval_hint,
    "bit" => @bit_hint,
    "varbit" => @bit_hint,
    "tsvector" => @text_search_hint,
    "tsquery" => @text_search_hint,
    "money" => @money_hint,
    "xml" => @xml_hint,
    "oid" => @oid_hint,
    "xid" => @oid_hint,
    "tid" => @oid_hint,
    "pg_lsn" => @oid_hint,
    "hstore" => @hstore_hint,
    "timetz" => @timetz_hint
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

  @spec hint_for(String.t(), String.t() | nil) :: String.t() | nil
  def hint_for(name, kind) when is_binary(name) do
    case hint_for(name) do
      nil -> kind_hint(kind)
      hint -> hint
    end
  end

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

  defp base_type(name, kind, _base) when kind in ["r", "m"] do
    {:error, unsupported_type(name, kind)}
  end

  defp base_type(name, kind, _base) do
    case Map.fetch(@base_types, name) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, unsupported_type(name, kind)}
    end
  end

  defp unsupported_composite(name) do
    %UnsupportedPostgresType{name: name, hint: @composite_hint}
  end

  defp unsupported_type(name, kind) do
    %UnsupportedPostgresType{name: name, hint: hint_for(name, kind)}
  end

  defp kind_hint("r"), do: @range_hint
  defp kind_hint("m"), do: @multirange_hint
  defp kind_hint("c"), do: @composite_hint
  defp kind_hint(_kind), do: nil

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
