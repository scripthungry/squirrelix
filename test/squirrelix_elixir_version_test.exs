defmodule SquirrelixElixirVersionTest do
  use ExUnit.Case, async: true

  describe "Elixir version floor" do
    test "matches mix.exs ~> 1.18 requirement" do
      assert Version.match?(System.version(), "~> 1.18")
    end

    test "stdlib JSON is available (1.18+ floor)" do
      assert Code.ensure_loaded?(JSON)
      assert function_exported?(JSON, :encode!, 1)
      assert function_exported?(JSON, :decode, 1)
    end
  end
end
