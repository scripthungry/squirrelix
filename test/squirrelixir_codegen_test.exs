defmodule SquirrelixirCodegenTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Codegen
  alias Squirrelixir.CodegenCheckSummary
  alias Squirrelixir.CodegenSummary
  alias Squirrelixir.Column
  alias Squirrelixir.Error.CannotReadFile
  alias Squirrelixir.Error.OutdatedFile
  alias Squirrelixir.Parameter
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

  test "generate_module emits formatted Elixir functions sorted by source file" do
    queries = [
      typed_query("z_last.sql", "z_last", "select * from users", []),
      typed_query(
        "a_first.sql",
        "find_user",
        "select * from users where id = $1",
        [
          %Parameter{index: 1, name: "id", type: :integer}
        ],
        [%Column{name: "name", type: :string, nullable?: false}]
      )
    ]

    assert Codegen.generate_module(MyApp.Accounts.SQL, queries, version: "v-test") == """
           defmodule MyApp.Accounts.SQL do
             @moduledoc \"\"\"
             This module contains generated query functions.

             > This module was generated automatically using Squirrelixir v-test.
             \"\"\"

             @spec find_user(Postgrex.conn(), integer()) :: [%{required(:name) => String.t()}]
             def find_user(connection, id) do
               connection
               |> Postgrex.query!("select * from users where id = $1", [id])
               |> decode_rows([:name])
             end

             @spec z_last(Postgrex.conn()) :: [%{required(:id) => integer()}]
             def z_last(connection) do
               connection
               |> Postgrex.query!("select * from users", [])
               |> decode_rows([:id])
             end

             defp decode_rows(%Postgrex.Result{rows: rows}, columns) do
               Enum.map(rows, &row_to_map(&1, columns))
             end

             defp row_to_map(row, columns) do
               columns
               |> Enum.zip(row)
               |> Map.new()
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
    assert code =~ ~s|Postgrex.query!("select $1, $2, $3", [arg_1, arg_2, arg_3])|
  end

  test "generate_module avoids Elixir reserved argument names" do
    query =
      typed_query("reserved.sql", "reserved", "select $1, $2, $3", [
        %Parameter{index: 1, name: "fn", type: :string},
        %Parameter{index: 2, name: "end", type: :string},
        %Parameter{index: 3, name: "type", type: :string}
      ])

    code =
      Codegen.generate_module(Squirrelixir.GeneratedReservedNamesTest.SQL, [query],
        version: "v-test"
      )

    assert code =~ "def reserved(connection, fn_, end_, type)"
    assert code =~ ~s|Postgrex.query!("select $1, $2, $3", [fn_, end_, type])|
    assert [{Squirrelixir.GeneratedReservedNamesTest.SQL, _bytecode}] = Code.compile_string(code)
  end

  test "generate_module avoids SQL literal argument names" do
    query =
      typed_query("literals.sql", "literals", "select $1, $2, $3", [
        %Parameter{index: 1, name: "true", type: :boolean},
        %Parameter{index: 2, name: "false", type: :boolean},
        %Parameter{index: 3, name: "null", type: :string}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "def literals(connection, arg_1, arg_2, arg_3)"
    assert code =~ ~s|Postgrex.query!("select $1, $2, $3", [arg_1, arg_2, arg_3])|
  end

  test "generate_module includes nullable columns in row specs" do
    query =
      typed_query("find_user.sql", "find_user", "select * from users", [], [
        %Column{name: "name", type: :string, nullable?: true},
        %Column{name: "age", type: :integer, nullable?: false}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "@spec find_user(Postgrex.conn()) ::"
    assert code =~ "required(:name) => String.t() | nil"
    assert code =~ "required(:age) => integer()"
  end

  test "generate_module maps utc datetimes to DateTime specs" do
    query =
      typed_query("events.sql", "events", "select now()", [], [
        %Column{name: "occurred_at", type: :utc_datetime, nullable?: false}
      ])

    assert Codegen.generate_module(MyApp.SQL, [query], version: "v-test") =~
             "required(:occurred_at) => DateTime.t()"
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

  test "generate_module emits code that compiles against Postgrex" do
    query =
      typed_query("find_user.sql", "find_user", "select * from users where id = $1", [
        %Parameter{index: 1, name: "id", type: :integer}
      ])

    code =
      Codegen.generate_module(Squirrelixir.GeneratedCompileTest.SQL, [query], version: "v-test")

    assert Code.ensure_loaded?(Postgrex)
    assert [{Squirrelixir.GeneratedCompileTest.SQL, _bytecode}] = Code.compile_string(code)
    assert function_exported?(Squirrelixir.GeneratedCompileTest.SQL, :find_user, 2)
  end

  test "generated functions return decoded row maps" do
    query =
      typed_query(
        "find_user.sql",
        "find_user",
        "select name from users where id = $1",
        [
          %Parameter{index: 1, name: "id", type: :integer}
        ],
        [%Column{name: "name", type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelixir.GeneratedRuntimeTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexMock
      )

    [{module, _bytecode}] = Code.compile_string(code)

    assert module.find_user({PostgrexMock, self()}, 123) == [%{name: "Ada"}]

    assert_received {:query!, "select name from users where id = $1", [123]}
  end

  test "generated command functions return ok" do
    query =
      typed_query(
        "insert_user.sql",
        "insert_user",
        "insert into users(name) values ($1)",
        [%Parameter{index: 1, name: "name", type: :string}],
        []
      )

    code =
      Codegen.generate_module(Squirrelixir.GeneratedCommandTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexCommandMock
      )

    assert code =~ "@spec insert_user(Postgrex.conn(), String.t()) :: :ok"

    [{module, _bytecode}] = Code.compile_string(code)

    assert module.insert_user({PostgrexCommandMock, self()}, "Ada") == :ok
    assert_received {:query!, "insert into users(name) values ($1)", ["Ada"]}
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

  test "check_directory returns ok when the generated output is current" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query = typed_query(Path.join(sql_directory, "find_user.sql"), "find_user", "select 1", [])

    assert Codegen.write_directory(root, sql_directory, [query], version: "v-test") == :ok
    assert Codegen.check_directory(root, sql_directory, [query], version: "v-test") == :ok
  end

  test "check_directory returns read and outdated errors" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query = typed_query(Path.join(sql_directory, "find_user.sql"), "find_user", "select 1", [])
    output_file = Path.join(root, "lib/accounts/sql.ex")

    assert Codegen.check_directory(root, sql_directory, [query], version: "v-test") ==
             {:error, %CannotReadFile{file: output_file, reason: :enoent}}

    File.write!(
      output_file,
      Codegen.generate_module(AcornCounter.Accounts.SQL, [], version: "v-test")
    )

    assert Codegen.check_directory(root, sql_directory, [query], version: "v-test") ==
             {:error, %OutdatedFile{file: output_file}}
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

  test "check_directories checks each typed query directory and returns outcomes" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    missing_dir = Path.join(root, "lib/missing/sql")

    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(missing_dir)

    directories = [
      %TypedQueryDirectory{
        directory: accounts_dir,
        queries: [typed_query(Path.join(accounts_dir, "account.sql"), "account", "select 1", [])]
      },
      %TypedQueryDirectory{
        directory: missing_dir,
        queries: [typed_query(Path.join(missing_dir, "missing.sql"), "missing", "select 2", [])]
      }
    ]

    assert Codegen.write_directory(root, accounts_dir, hd(directories).queries, version: "v-test") ==
             :ok

    assert [
             {^accounts_dir, :ok, 1},
             {^missing_dir, {:error, %CannotReadFile{}}, 1}
           ] = Codegen.check_directories(root, directories, version: "v-test")
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

  test "summarize_check_outcomes counts checked queries and collects errors" do
    assert Codegen.summarize_check_outcomes([
             {"lib/accounts/sql", :ok, 2},
             {"lib/billing/sql", {:error, :missing}, 1}
           ]) == %CodegenCheckSummary{
             checked_count: 2,
             errors: [{"lib/billing/sql", :missing}],
             status: :error
           }
  end

  test "summarize_check_outcomes reports no queries" do
    assert Codegen.summarize_check_outcomes([]) == %CodegenCheckSummary{
             checked_count: 0,
             errors: [],
             status: :empty
           }
  end

  defp typed_query(file, name, content, params, returns \\ nil) do
    %TypedQuery{
      file: file,
      starting_line: 1,
      name: name,
      comment: [],
      content: content,
      params: params,
      returns: returns || [%Column{name: "id", type: :integer, nullable?: false}]
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

defmodule PostgrexMock do
  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["name"], rows: [["Ada"]]}
  end
end

defmodule PostgrexCommandMock do
  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{command: :insert, columns: nil, rows: nil, num_rows: 1}
  end
end
