defmodule SquirrelixirGenerateTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.CodegenCheckSummary
  alias Squirrelixir.CodegenSummary

  test "generate discovers SQL files, writes generated modules, and returns a summary" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts where id = $1")

    metadata = %{
      query_file => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert Squirrelixir.generate(root, metadata, version: "v-test") == %CodegenSummary{
             generated_count: 1,
             errors: [],
             status: :ok
           }

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~
             "defmodule AcornCounter.Accounts.SQL do"
  end

  test "generate reports directory errors without writing generated modules" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "01 invalid.sql")
    File.write!(query_file, "select 1")

    assert %CodegenSummary{
             generated_count: 0,
             errors: [{^sql_directory, [_error]}],
             status: :error
           } = Squirrelixir.generate(root, %{}, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
  end

  test "generate reports missing metadata without writing generated modules" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts")

    assert %CodegenSummary{
             generated_count: 0,
             errors: [
               {^sql_directory, [%Squirrelixir.Error.MissingQueryMetadata{file: ^query_file}]}
             ],
             status: :error
           } = Squirrelixir.generate(root, %{}, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
  end

  test "check discovers SQL files and reports generated modules are current" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts where id = $1")

    metadata = %{
      query_file => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert Squirrelixir.generate(root, metadata, version: "v-test").status == :ok

    assert Squirrelixir.check(root, metadata, version: "v-test") == %CodegenCheckSummary{
             checked_count: 1,
             errors: [],
             status: :ok
           }
  end

  test "check reports missing generated modules without writing them" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts")

    metadata = %{
      query_file => [
        params: [],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert %CodegenCheckSummary{
             checked_count: 0,
             errors: [{^sql_directory, %Squirrelixir.Error.CannotReadFile{reason: :enoent}}],
             status: :error
           } = Squirrelixir.check(root, metadata, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
  end

  defp tmp_project(app) do
    path = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-generate")

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
