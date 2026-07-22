defmodule SquirrElixGleamParityTest do
  @moduledoc """
  Gleam Squirrel upstream parity reference.

  Maps every `pub fn *_test()` in Gleam's `test/squirrel_test.gleam` and
  `test/integration_test.gleam` to ExUnit coverage. See module doc in the
  commit message / ROADMAP for the full audit table.

  ## Intentional Elixir differences (no ExUnit port)

  The following Gleam Birdie snapshot tests are intentionally not ported because
  SquirrElix generates idiomatic Elixir instead of Gleam ADTs and pipeline code:

  * `generated_type_has_the_same_name_as_the_function_but_in_pascal_case_test` —
    Elixir row types use `query_row` maps, not PascalCase Gleam custom types.
  * `query_that_needs_utils_and_enums_has_two_sections_test` and
    `multiple_enums_are_properly_separated_by_an_empty_line_test` — no generated
    enum ADT modules or `# --- Enums ---` section; Postgres enums map to `String.t()`.
  * `decode_success_with_long_builder_is_properly_formatted_*` —
    Gleam pipeline line-break formatting; Elixir uses plain function calls.
  * `very_long_argument_name_is_broken_when_passed_as_pipeline_argument_test` —
    Gleam pipeline wrapping; Elixir keeps long argument names on one line.
  * `when_using_a_list_as_argument_the_list_module_is_imported_test` —
    Gleam `import gleam/list`; Elixir uses built-in `Enum` without imports.
  * `parameter_name_keyword_is_not_used_in_gleam_code_test` — Gleam keyword `type`;
    Elixir allows `type` as a function argument (see codegen reserved-name tests).
  * `enum_with_invalid_name_test` and `enum_with_invalid_variant_test` — Gleam rejects
    non-identifier enum names/variants at codegen; Elixir maps custom enums to `String.t()`.
  * `integration_test_` — Gleam compiles a throwaway Gleam project; Elixir uses
    `SquirrElixIntegrationTest` with Mix projects and Postgrex mocks instead.
  """

  use ExUnit.Case, async: true

  # Behavioral ports for codegen structure that Birdie snapshots covered in Gleam
  # but were only partially asserted in Elixir until this audit.

  alias SquirrElix.Codegen
  alias SquirrElix.Column
  alias SquirrElix.TypedQuery

  test "generate_module labels row fields from select list names and aliases" do
    query =
      typed_query(
        "find_squirrel.sql",
        "find_squirrel",
        "select acorns, name as squirrel_name from squirrel",
        [],
        [
          %Column{name: "acorns", type: :integer, nullable?: false},
          %Column{name: "squirrel_name", type: :string, nullable?: false}
        ]
      )

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "@type find_squirrel_row ::"
    assert code =~ "required(:acorns) => integer()"
    assert code =~ "required(:squirrel_name) => String.t()"
    assert code =~ "{:acorns, :integer, false}"
    assert code =~ "{:squirrel_name, :string, false}"
  end

  test "generate_module marks outer-join columns nullable in row specs" do
    query =
      typed_query(
        "left_join.sql",
        "left_join",
        """
        select
          s1.name as not_optional,
          s2.name as optional
        from
          squirrel s1
          left join squirrel s2 using(name)
        """,
        [],
        [
          %Column{name: "not_optional", type: :string, nullable?: false},
          %Column{name: "optional", type: :string, nullable?: true}
        ]
      )

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "required(:not_optional) => String.t()"
    assert code =~ "required(:optional) => String.t() | nil"
    assert code =~ "{:optional, :string, true}"
  end

  test "generate_module emits uuid and date helpers when both types appear" do
    query =
      typed_query(
        "mixed_helpers.sql",
        "mixed_helpers",
        "select gen_random_uuid(), 'Jan-2-1970'::date",
        [],
        [
          %Column{name: "gen_random_uuid", type: :uuid, nullable?: false},
          %Column{name: "date", type: :date, nullable?: false}
        ]
      )

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "defp uuid_to_string("
    assert code =~ "defp decode_scalar(value, :date)"
    assert [{_module, _bytecode}] = Code.compile_string(code)
  end

  test "generate_module compiles when query uses a long postgres enum type name" do
    long_enum = "issue_114_aaaaaaaaaaaaaaaaa"

    query =
      typed_query(
        "long_enum.sql",
        "long_enum",
        "select 'wibble'::#{long_enum}",
        [],
        [%Column{name: long_enum, type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(SquirrElix.GleamParityLongEnumTest.SQL, [query], version: "v-test")

    assert code =~ "required(:#{long_enum}) => String.t()"
    refute code =~ "# --- Enums ---"
    assert [{SquirrElix.GleamParityLongEnumTest.SQL, _bytecode}] = Code.compile_string(code)
  end

  defp typed_query(file, name, content, params, returns) do
    %TypedQuery{
      file: file,
      starting_line: 1,
      name: name,
      comment: [],
      content: content,
      params: params,
      returns: returns
    }
  end
end
