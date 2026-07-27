defmodule SquirrelixTypeMapperTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Error.UnsupportedPostgresType
  alias Squirrelix.TypeMapper

  test "from_postgres maps built-in Postgres types to Elixir type atoms" do
    assert TypeMapper.from_postgres("bool") == {:ok, :boolean}
    assert TypeMapper.from_postgres("text") == {:ok, :string}
    assert TypeMapper.from_postgres("varchar") == {:ok, :string}
    assert TypeMapper.from_postgres("int4") == {:ok, :integer}
    assert TypeMapper.from_postgres("float8") == {:ok, :float}
    assert TypeMapper.from_postgres("numeric") == {:ok, :decimal}
    assert TypeMapper.from_postgres("jsonb") == {:ok, :map}
    assert TypeMapper.from_postgres("uuid") == {:ok, :uuid}
    assert TypeMapper.from_postgres("bytea") == {:ok, :binary}
    assert TypeMapper.from_postgres("date") == {:ok, :date}
    assert TypeMapper.from_postgres("time") == {:ok, :time}
    assert TypeMapper.from_postgres("timestamp") == {:ok, :naive_datetime}
    assert TypeMapper.from_postgres("timestamptz") == {:ok, :utc_datetime}
  end

  test "from_postgres wraps array types as lists" do
    assert TypeMapper.from_postgres("int4", array_dimensions: 1) == {:ok, {:list, :integer}}

    assert TypeMapper.from_postgres("text", array_dimensions: 2) ==
             {:ok, {:list, {:list, :string}}}
  end

  test "from_postgres maps custom Postgres enums to strings" do
    assert TypeMapper.from_postgres("squirr_elix_mood", kind: "e") == {:ok, :string}

    assert TypeMapper.from_postgres("squirr_elix_mood", kind: "e", array_dimensions: 1) ==
             {:ok, {:list, :string}}
  end

  test "from_postgres maps custom Postgres domains to their base type" do
    assert TypeMapper.from_postgres("squirr_elix_email", kind: "d", base: "text") ==
             {:ok, :string}

    assert TypeMapper.from_postgres("squirr_elix_email",
             kind: "d",
             base: "text",
             array_dimensions: 1
           ) == {:ok, {:list, :string}}
  end

  test "from_postgres rejects unsupported types with actionable hints" do
    assert {:error, %UnsupportedPostgresType{name: "point", hint: hint}} =
             TypeMapper.from_postgres("point")

    assert hint =~ "Geometric"
  end

  test "hint_for returns guidance for timestamptz and point" do
    assert TypeMapper.hint_for("timestamptz") =~ "time zone"
    assert TypeMapper.hint_for("point") =~ "Geometric"
  end

  test "validate_enum accepts any enum name and variant strings" do
    assert :ok = TypeMapper.validate_enum("squirrel_mood", ["happy", "sleepy"])
    assert :ok = TypeMapper.validate_enum("1 invalid enum", ["value"])
    assert :ok = TypeMapper.validate_enum("invalid_variant", ["1 invalid value"])
  end

  test "validate_enum rejects enums with no variants" do
    assert {:error, :no_variants} = TypeMapper.validate_enum("no_variants", [])
  end

  test "typespec maps internal types to Elixir stdlib typespecs" do
    assert TypeMapper.typespec(:integer) == "integer()"
    assert TypeMapper.typespec(:string) == "String.t()"
    assert TypeMapper.typespec(:decimal) == "Decimal.t()"
    assert TypeMapper.typespec(:date) == "Date.t()"
    assert TypeMapper.typespec(:time) == "Time.t()"
    assert TypeMapper.typespec(:naive_datetime) == "NaiveDateTime.t()"
    assert TypeMapper.typespec(:utc_datetime) == "DateTime.t()"
    assert TypeMapper.typespec(:uuid) == "String.t()"
    assert TypeMapper.typespec({:list, :string}) == "[String.t()]"
    assert TypeMapper.typespec(:map) == "term()"
  end

  test "typespec maps postgres enums to String.t()" do
    assert TypeMapper.from_postgres("squirrel_mood", kind: "e") == {:ok, :string}
    assert TypeMapper.typespec(:string) == "String.t()"
  end

  test "return_typespec builds map types with required keys" do
    assert TypeMapper.return_typespec([]) == ":ok"

    columns = [{:name, :string, true}, {:age, :integer, false}]

    assert TypeMapper.row_typespec(columns) ==
             "%{required(:name) => String.t() | nil, required(:age) => integer()}"

    assert TypeMapper.return_typespec(columns) == "[#{TypeMapper.row_typespec(columns)}]"
  end

  test "normalize_type accepts Elixir atoms and Postgres descriptors" do
    assert TypeMapper.normalize_type(:integer) == {:ok, :integer}
    assert TypeMapper.normalize_type({:postgres, "int4"}) == {:ok, :integer}

    assert TypeMapper.normalize_type(%{postgres: "text", array_dimensions: 1}) ==
             {:ok, {:list, :string}}
  end

  describe "postgres string types and unsupported built-ins" do
    test "from_postgres maps char-like Postgres types to string" do
      for type <- ~w(char bpchar citext name) do
        assert TypeMapper.from_postgres(type) == {:ok, :string}
      end
    end

    test "from_postgres wraps name arrays as string lists" do
      assert TypeMapper.from_postgres("name", array_dimensions: 1) == {:ok, {:list, :string}}
    end

    test "hint_for returns timestamptz guidance matching upstream Squirrel" do
      hint = TypeMapper.hint_for("timestamptz")

      assert hint =~ "timestamptz"
      assert hint =~ "time zone"
      assert hint =~ "error prone"
      assert hint =~ "regular timestamps"
    end

    test "from_postgres rejects point with a geometric hint" do
      assert {:error, %UnsupportedPostgresType{name: "point", hint: hint}} =
               TypeMapper.from_postgres("point")

      assert hint =~ "Geometric"
    end

    test "from_postgres rejects composite kinds with an actionable composite-type hint" do
      assert {:error, %UnsupportedPostgresType{name: "squirr_elix_point", hint: hint}} =
               TypeMapper.from_postgres("squirr_elix_point", kind: "c")

      assert hint =~ "composite"
      assert hint =~ ~r/field|json|text/i

      assert {:error, %UnsupportedPostgresType{name: "squirr_elix_point", hint: ^hint}} =
               TypeMapper.from_postgres("squirr_elix_point", kind: "c", array_dimensions: 1)
    end

    test "normalize_type rejects composite Postgres descriptors with hints" do
      assert {:error, %UnsupportedPostgresType{name: "address", hint: hint}} =
               TypeMapper.normalize_type(%{postgres: "address", kind: "c"})

      assert hint =~ "composite"
    end

    test "from_postgres rejects unknown names without a kind-specific hint" do
      assert TypeMapper.from_postgres("squirr_elix_point") ==
               {:error, %UnsupportedPostgresType{name: "squirr_elix_point", hint: nil}}
    end
  end

  describe "composite type policy" do
    test "composites remain unsupported rather than mapping to maps or generated types" do
      # Policy (issue #4): reject-with-hints. Do not map composites to map()/term()
      # or generate nested row modules — that would expand the Elixir-native surface
      # beyond Gleam Squirrel and dilute typed row maps.
      assert {:error, %UnsupportedPostgresType{hint: hint}} =
               TypeMapper.from_postgres("inventory_item", kind: "c")

      refute hint == nil
      assert hint =~ "composite"
      refute match?({:ok, :map}, TypeMapper.from_postgres("inventory_item", kind: "c"))
      refute match?({:ok, :string}, TypeMapper.from_postgres("inventory_item", kind: "c"))
    end
  end

  describe "postgres ranges and remaining unsupported built-ins" do
    @range_types ~w(int4range int8range numrange tsrange tstzrange daterange)
    @multirange_types ~w(
      int4multirange int8multirange nummultirange tsmultirange tstzmultirange datemultirange
    )
    @geometric_types ~w(point box circle line lseg path polygon)
    @network_types ~w(inet cidr macaddr macaddr8)
    @other_unsupported ~w(interval bit varbit tsvector tsquery money xml oid xid tid pg_lsn hstore timetz)

    test "from_postgres rejects built-in range types with range hints" do
      for type <- @range_types do
        assert {:error, %UnsupportedPostgresType{name: ^type, hint: hint}} =
                 TypeMapper.from_postgres(type)

        assert hint =~ "range"
        assert hint =~ "bounds" or hint =~ "lower" or hint =~ "upper" or hint =~ "text"
      end
    end

    test "from_postgres rejects built-in multirange types with range hints" do
      for type <- @multirange_types do
        assert {:error, %UnsupportedPostgresType{name: ^type, hint: hint}} =
                 TypeMapper.from_postgres(type)

        assert hint =~ "range"
      end
    end

    test "from_postgres rejects range and multirange kinds for custom names" do
      assert {:error, %UnsupportedPostgresType{name: "floatrange", hint: hint}} =
               TypeMapper.from_postgres("floatrange", kind: "r")

      assert hint =~ "range"

      assert {:error, %UnsupportedPostgresType{name: "floatmultirange", hint: hint}} =
               TypeMapper.from_postgres("floatmultirange", kind: "m")

      assert hint =~ "range"
    end

    test "from_postgres rejects geometric built-ins with geometric hints" do
      for type <- @geometric_types do
        assert {:error, %UnsupportedPostgresType{name: ^type, hint: hint}} =
                 TypeMapper.from_postgres(type)

        assert hint =~ "Geometric"
      end
    end

    test "from_postgres rejects network built-ins with network hints" do
      for type <- @network_types do
        assert {:error, %UnsupportedPostgresType{name: ^type, hint: hint}} =
                 TypeMapper.from_postgres(type)

        assert hint =~ "Network" or hint =~ "text"
      end
    end

    test "from_postgres rejects remaining unsupported built-ins with actionable hints" do
      for type <- @other_unsupported do
        assert {:error, %UnsupportedPostgresType{name: ^type, hint: hint}} =
                 TypeMapper.from_postgres(type)

        assert is_binary(hint)
        assert hint != ""
      end
    end

    test "hint_for documents range and unsupported built-in guidance" do
      assert TypeMapper.hint_for("int4range") =~ "range"
      assert TypeMapper.hint_for("inet") =~ "text"
      assert TypeMapper.hint_for("interval") =~ "interval"
      assert TypeMapper.hint_for("money") =~ "numeric"
    end
  end
end
