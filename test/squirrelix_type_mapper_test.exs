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

    assert hint =~ "point"
    assert hint =~ ~r/text|json|numeric/i
  end

  test "hint_for returns guidance for timestamptz and point" do
    assert TypeMapper.hint_for("timestamptz") =~ "time zone"
    assert TypeMapper.hint_for("point") =~ "point"
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

    test "from_postgres rejects point with an actionable geometric-type hint" do
      assert {:error, %UnsupportedPostgresType{name: "point", hint: hint}} =
               TypeMapper.from_postgres("point")

      assert hint =~ "point"
      assert hint =~ ~r/text|json|numeric/i
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
end
