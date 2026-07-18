defmodule SquirrelixirCodegenTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Column
  alias Squirrelixir.Parameter
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.Codegen

  test "generate_module emits formatted Elixir functions sorted by source file" do
    queries = [
      typed_query("z_last.sql", "z_last", "select * from users", []),
      typed_query("a_first.sql", "find_user", "select * from users where id = $1", [
        %Parameter{index: 1, name: "id", type: :integer}
      ])
    ]

    assert Codegen.generate_module(MyApp.Accounts.SQL, queries, version: "v-test") == """
           defmodule MyApp.Accounts.SQL do
             @moduledoc \"\"\"
             This module contains generated query functions.

             > This module was generated automatically using Squirrelixir v-test.
             \"\"\"

             @spec find_user(Postgrex.conn(), integer()) :: Postgrex.Result.t()
             def find_user(connection, id) do
               Postgrex.query!(connection, \"select * from users where id = $1\", [id])
             end

             @spec z_last(Postgrex.conn()) :: Postgrex.Result.t()
             def z_last(connection) do
               Postgrex.query!(connection, \"select * from users\", [])
             end
           end
           """
  end

  test "generate_module uses fallback argument names when SQL inference could not name a parameter" do
    query =
      typed_query("search.sql", "search", "select * from users where $1 is null", [
        %Parameter{index: 1, name: nil, type: :string}
      ])

    assert Codegen.generate_module(MyApp.SQL, [query], version: "v-test") =~
             "def search(connection, arg_1)"
  end

  test "generate_module output is classified as generated" do
    query = typed_query("all.sql", "all", "select * from users", [])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert Squirrelixir.classify_file_content(code) == :likely_generated
  end

  test "generate_module emits query comments as function docs" do
    query = %TypedQuery{
      typed_query("find_user.sql", "find_user", "select * from users", [])
      | comment: ["Finds a user.", "Returns every matching row."]
    }

    assert Codegen.generate_module(MyApp.SQL, [query], version: "v-test") =~
             ~s|@doc """\n  Finds a user.\n  Returns every matching row.\n  """|
  end

  defp typed_query(file, name, content, params) do
    %TypedQuery{
      file: file,
      starting_line: 1,
      name: name,
      comment: [],
      content: content,
      params: params,
      returns: [%Column{name: "id", type: :integer, nullable?: false}]
    }
  end
end
