defmodule SquirrelixirQueryCompatibilityTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Error.QueryFileHasInvalidName
  alias Squirrelixir.Query

  test "from_file reads a query and derives its name from the file basename" do
    path = write_temp_sql("find_squirrels.sql", "select * from squirrels")

    assert {:ok,
            %Query{
              file: ^path,
              starting_line: 1,
              name: "find_squirrels",
              comment: [],
              content: "select * from squirrels"
            }} = Query.from_file(path)
  end

  test "from_file accepts Elixir predicate and bang function names" do
    predicate_path = write_temp_sql("active?.sql", "select true")
    bang_path = write_temp_sql("save!.sql", "insert into squirrels values (1)")

    assert {:ok, %Query{name: "active?"}} = Query.from_file(predicate_path)
    assert {:ok, %Query{name: "save!"}} = Query.from_file(bang_path)
  end

  test "from_file preserves query content exactly" do
    content = "\n  select *\n  from squirrels\n  where acorns > $1\n"
    path = write_temp_sql("exact_content.sql", content)

    assert {:ok, %Query{content: ^content}} = Query.from_file(path)
  end

  test "from_file takes leading sql comments after trimming leading whitespace" do
    path =
      write_temp_sql("with_comments.sql", "\n\n-- first comment\n  -- second comment  \nselect 1")

    assert {:ok, %Query{comment: ["first comment", "second comment"]}} =
             Query.from_file(path)
  end

  test "from_file rejects invalid query file names with a suggestion when possible" do
    path = write_temp_sql("01 Find Squirrels.sql", "select 1")

    assert {:error,
            %QueryFileHasInvalidName{
              file: ^path,
              reason: {:invalid_grapheme, 0, "0"},
              suggested_name: "find_squirrels"
            }} = Query.from_file(path)
  end

  test "from_file rejects empty query file names without a suggestion" do
    path = write_temp_sql(".sql", "select 1")

    assert {:error,
            %QueryFileHasInvalidName{
              file: ^path,
              reason: :empty,
              suggested_name: nil
            }} = Query.from_file(path)
  end

  defp write_temp_sql(file_name, content) do
    dir = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-query")
    path = Path.join(dir, file_name)
    File.write!(path, content)
    path
  end
end
