defmodule SquirrelixCompatibilityTest do
  use ExUnit.Case, async: true

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
    assert Squirrelix.compare_code_snippets(@generated_code, @generated_code) ==
             :same
  end

  test "if code snippets differ by formatting they are the same" do
    actual_code =
      @generated_code
      |> String.split("\n")
      |> Enum.map_join("\n", fn line -> if line == "", do: line, else: "  " <> line end)

    assert Squirrelix.compare_code_snippets(@generated_code, actual_code) == :same
  end

  test "if code snippets differ by comments they are the same" do
    actual_code = "// Comment!\n" <> @generated_code

    assert Squirrelix.compare_code_snippets(@generated_code, actual_code) == :same
  end

  test "if Elixir code snippets differ by comments they are the same" do
    expected_code = """
    defmodule Generated do
      def all(connection), do: connection
    end
    """

    actual_code = """
    # Generated query module
    defmodule Generated do
      # Runs the query
      def all(connection), do: connection
    end
    """

    assert Squirrelix.compare_code_snippets(expected_code, actual_code) == :same
  end

  test "comparing different snippets of code" do
    actual_code = String.replace(@generated_code, "Ok(1)", "Ok(2)")

    assert Squirrelix.compare_code_snippets(@generated_code, actual_code) ==
             :different
  end

  test "file with squirrel module comment is considered as generated" do
    assert Squirrelix.classify_file_content(@generated_code) == :likely_generated
  end

  test "file with only squirrel function comment is not considered generated" do
    code_without_module_comment =
      @generated_code
      |> String.split("\n")
      |> Enum.reject(&String.starts_with?(&1, "////"))
      |> Enum.join("\n")

    assert Squirrelix.classify_file_content(code_without_module_comment) ==
             :not_generated
  end

  test "generation marker buried outside the header is not trusted" do
    buried =
      String.duplicate("a", 3_000) <>
        "\n> This module was generated automatically using Squirrelix v0.1.0\n"

    assert Squirrelix.classify_file_content(buried) == :not_generated
  end
end
