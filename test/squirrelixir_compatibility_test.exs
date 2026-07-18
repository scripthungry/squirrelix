defmodule SquirrelixirCompatibilityTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.CheckResult
  alias Squirrelixir.FileOrigin

  @generated_code """
  //// > 🐿️ This module was generated automatically using Squirrel v4.7.0
  pub fn query(connection) {
    // > 🐿️ This function was generated automatically using Squirrel v4.7.0
    let decoder = fn(_dynamic) { Ok(1) }
    let result = 1
    Ok(result)
  }
  """

  test "checking two identical snippets of code" do
    assert Squirrelixir.compare_code_snippets(@generated_code, @generated_code) ==
             CheckResult.same()
  end

  test "if code snippets differ by formatting they are the same" do
    actual_code =
      @generated_code
      |> String.split("\n")
      |> Enum.map_join("\n", fn line -> if line == "", do: line, else: "  " <> line end)

    assert Squirrelixir.compare_code_snippets(@generated_code, actual_code) == CheckResult.same()
  end

  test "if code snippets differ by comments they are the same" do
    actual_code = "// Comment!\n" <> @generated_code

    assert Squirrelixir.compare_code_snippets(@generated_code, actual_code) == CheckResult.same()
  end

  test "comparing different snippets of code" do
    actual_code = String.replace(@generated_code, "Ok(1)", "Ok(2)")

    assert Squirrelixir.compare_code_snippets(@generated_code, actual_code) ==
             CheckResult.different()
  end

  test "file with squirrel module comment is considered as generated" do
    assert Squirrelixir.classify_file_content(@generated_code) == FileOrigin.likely_generated()
  end

  test "file with squirrel function comment is considered as generated" do
    code_without_module_comment =
      @generated_code
      |> String.split("\n")
      |> Enum.reject(&String.starts_with?(&1, "////"))
      |> Enum.join("\n")

    assert Squirrelixir.classify_file_content(code_without_module_comment) ==
             FileOrigin.likely_generated()
  end
end
