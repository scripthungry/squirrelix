defmodule SquirrelixirTypeMapperTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Error.UnsupportedPostgresType
  alias Squirrelixir.TypeMapper

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
    assert TypeMapper.from_postgres("squirrelixir_mood", kind: "e") == {:ok, :string}

    assert TypeMapper.from_postgres("squirrelixir_mood", kind: "e", array_dimensions: 1) ==
             {:ok, {:list, :string}}
  end

  test "from_postgres maps custom Postgres domains to their base type" do
    assert TypeMapper.from_postgres("squirrelixir_email", kind: "d", base: "text") ==
             {:ok, :string}

    assert TypeMapper.from_postgres("squirrelixir_email",
             kind: "d",
             base: "text",
             array_dimensions: 1
           ) == {:ok, {:list, :string}}
  end

  test "from_postgres rejects unsupported types" do
    assert TypeMapper.from_postgres("point") ==
             {:error, %UnsupportedPostgresType{name: "point", hint: nil}}
  end

  test "hint_for returns timestamptz guidance from upstream Squirrel" do
    assert TypeMapper.hint_for("timestamptz") =~ "time zone"
    assert TypeMapper.hint_for("point") == nil
  end

  test "validate_enum accepts snake_case enum names and variants" do
    assert :ok = TypeMapper.validate_enum("squirrel_mood", ["happy", "sleepy"])
  end

  test "validate_enum rejects enum names that cannot become type identifiers" do
    assert {:error, {:invalid_name, "1 invalid enum"}} =
             TypeMapper.validate_enum("1 invalid enum", ["value"])
  end

  test "validate_enum rejects enum variants that cannot become type identifiers" do
    assert {:error, {:invalid_variants, ["1 invalid value"]}} =
             TypeMapper.validate_enum("invalid_variant", ["1 invalid value"])
  end

  test "validate_enum rejects enums with no variants" do
    assert {:error, :no_variants} = TypeMapper.validate_enum("no_variants", [])
  end

  test "normalize_type accepts Elixir atoms and Postgres descriptors" do
    assert TypeMapper.normalize_type(:integer) == {:ok, :integer}
    assert TypeMapper.normalize_type({:postgres, "int4"}) == {:ok, :integer}

    assert TypeMapper.normalize_type(%{postgres: "text", array_dimensions: 1}) ==
             {:ok, {:list, :string}}
  end
end
