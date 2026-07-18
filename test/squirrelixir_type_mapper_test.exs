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
  end

  test "from_postgres wraps array types as lists" do
    assert TypeMapper.from_postgres("int4", array_dimensions: 1) == {:ok, {:list, :integer}}

    assert TypeMapper.from_postgres("text", array_dimensions: 2) ==
             {:ok, {:list, {:list, :string}}}
  end

  test "from_postgres rejects unsupported types" do
    assert TypeMapper.from_postgres("point") ==
             {:error, %UnsupportedPostgresType{name: "point"}}
  end

  test "normalize_type accepts Elixir atoms and Postgres descriptors" do
    assert TypeMapper.normalize_type(:integer) == {:ok, :integer}
    assert TypeMapper.normalize_type({:postgres, "int4"}) == {:ok, :integer}

    assert TypeMapper.normalize_type(%{postgres: "text", array_dimensions: 1}) ==
             {:ok, {:list, :string}}
  end
end
