defmodule SquirrelixirEnumTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Enum, as: SquirrelEnum

  test "validate accepts snake_case enum names and variants" do
    assert :ok = SquirrelEnum.validate("squirrel_mood", ["happy", "sleepy"])
  end

  test "validate rejects enum names that cannot become type identifiers" do
    assert {:error, {:invalid_name, "1 invalid enum"}} =
             SquirrelEnum.validate("1 invalid enum", ["value"])
  end

  test "validate rejects enum variants that cannot become type identifiers" do
    assert {:error, {:invalid_variants, ["1 invalid value"]}} =
             SquirrelEnum.validate("invalid_variant", ["1 invalid value"])
  end

  test "validate rejects enums with no variants" do
    assert {:error, :no_variants} = SquirrelEnum.validate("no_variants", [])
  end
end
