defmodule MixTasksSquirrelixirTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("squirrelixir.gen")
    Mix.Task.reenable("squirrelixir.check")

    :ok
  end

  test "mix squirrelixir.gen loads metadata and writes generated modules" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    write_metadata(root, query_file)

    output =
      File.cd!(root, fn ->
        capture_io(fn -> Mix.Task.run("squirrelixir.gen", []) end)
      end)

    assert output =~ "Generated 1 query."

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~
             "defmodule AcornCounter.Accounts.SQL do"
  end

  test "mix squirrelixir.check loads metadata and checks generated modules" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    write_metadata(root, query_file)

    File.cd!(root, fn ->
      capture_io(fn -> Mix.Task.run("squirrelixir.gen", []) end)
      Mix.Task.reenable("squirrelixir.check")

      output = capture_io(fn -> Mix.Task.run("squirrelixir.check", []) end)

      assert output =~ "All 1 query current."
    end)
  end

  test "mix squirrelixir.gen accepts a custom metadata file" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    metadata_file = Path.join(root, "config/squirrelixir.exs")
    write_metadata(root, query_file, metadata_file)

    output =
      File.cd!(root, fn ->
        capture_io(fn -> Mix.Task.run("squirrelixir.gen", ["--metadata", metadata_file]) end)
      end)

    assert output =~ "Generated 1 query."
  end

  test "mix squirrelixir.gen can infer metadata from Postgres" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")

    output =
      File.cd!(root, fn ->
        capture_io(fn ->
          Mix.Task.run("squirrelixir.gen", ["--infer", "--database", "postgres"])
        end)
      end)

    assert output =~ "Generated 1 query."
    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "required(:name) => String.t()"
  end

  defp tmp_project(app) do
    path = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-mix-task")

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

  defp write_query(root, content \\ "select name from accounts where id = $1") do
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, content)

    query_file
  end

  defp write_metadata(root, query_file, metadata_file \\ nil) do
    metadata_file = metadata_file || Path.join(root, "squirrelixir.exs")
    relative_query_file = Path.relative_to(query_file, root)

    File.mkdir_p!(Path.dirname(metadata_file))

    File.write!(metadata_file, """
    %{
      #{inspect(relative_query_file)} => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }
    """)
  end
end
