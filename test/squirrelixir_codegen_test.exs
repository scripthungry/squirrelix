defmodule SquirrelixirCodegenTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Codegen
  alias Squirrelixir.CodegenSummary
  alias Squirrelixir.Column
  alias Squirrelixir.Parameter
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

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

  test "generate_module deconflicts argument names" do
    query =
      typed_query("conflicting.sql", "conflicting", "select $1, $2, $3", [
        %Parameter{index: 1, name: "connection", type: :string},
        %Parameter{index: 2, name: "connection", type: :string},
        %Parameter{index: 3, name: "arg_1", type: :string}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "def conflicting(connection, arg_1, arg_2, arg_3)"
    assert code =~ ~s|Postgrex.query!(connection, "select $1, $2, $3", [arg_1, arg_2, arg_3])|
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

  test "write_directory writes a generated module next to the sql directory" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query =
      typed_query(
        Path.join(sql_directory, "find_user.sql"),
        "find_user",
        "select * from users",
        []
      )

    assert Codegen.write_directory(root, sql_directory, [query], version: "v-test") == :ok

    output_file = Path.join(root, "lib/accounts/sql.ex")
    assert File.exists?(output_file)

    assert File.read!(output_file) =~ "defmodule AcornCounter.Accounts.SQL do"
    assert File.read!(output_file) =~ "def find_user(connection)"
  end

  test "write_directory returns error for sql directories outside project source roots" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "priv/sql")
    File.mkdir_p!(sql_directory)

    query =
      typed_query(
        Path.join(sql_directory, "find_user.sql"),
        "find_user",
        "select * from users",
        []
      )

    assert Codegen.write_directory(root, sql_directory, [query], version: "v-test") ==
             {:error, :invalid_sql_directory}
  end

  test "write_directories writes each typed query directory and returns outcomes" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    billing_dir = Path.join(root, "lib/billing/sql")

    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(billing_dir)

    directories = [
      %TypedQueryDirectory{
        directory: billing_dir,
        queries: [typed_query(Path.join(billing_dir, "invoice.sql"), "invoice", "select 2", [])]
      },
      %TypedQueryDirectory{
        directory: accounts_dir,
        queries: [typed_query(Path.join(accounts_dir, "account.sql"), "account", "select 1", [])]
      }
    ]

    assert Codegen.write_directories(root, directories, version: "v-test") == [
             {accounts_dir, :ok, 1},
             {billing_dir, :ok, 1}
           ]

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "def account(connection)"
    assert File.read!(Path.join(root, "lib/billing/sql.ex")) =~ "def invoice(connection)"
  end

  test "summarize_write_outcomes counts generated queries and collects errors" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    invalid_dir = Path.join(root, "priv/sql")

    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(invalid_dir)

    outcomes =
      Codegen.write_directories(
        root,
        [
          %TypedQueryDirectory{
            directory: accounts_dir,
            queries: [
              typed_query(Path.join(accounts_dir, "account.sql"), "account", "select 1", []),
              typed_query(Path.join(accounts_dir, "accounts.sql"), "accounts", "select 2", [])
            ]
          },
          %TypedQueryDirectory{
            directory: invalid_dir,
            queries: [
              typed_query(Path.join(invalid_dir, "invalid.sql"), "invalid", "select 3", [])
            ]
          }
        ],
        version: "v-test"
      )

    assert Codegen.summarize_write_outcomes(outcomes) == %CodegenSummary{
             generated_count: 2,
             errors: [{invalid_dir, :invalid_sql_directory}],
             status: :error
           }
  end

  test "summarize_write_outcomes reports no queries" do
    assert Codegen.summarize_write_outcomes([]) == %CodegenSummary{
             generated_count: 0,
             errors: [],
             status: :empty
           }
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

  defp tmp_project(app) do
    path = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-codegen")

    File.write!(Path.join(path, "mix.exs"), """
    defmodule TempProject.MixProject do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0"]
      end
    end
    """)

    path
  end
end
