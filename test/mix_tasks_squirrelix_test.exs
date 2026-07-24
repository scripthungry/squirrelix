defmodule MixTasksSquirrelixTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    Mix.Task.reenable("squirrelix.gen")
    Mix.Task.reenable("squirrelix.check")

    :ok
  end

  test "mix squirrelix.gen loads metadata and writes generated modules" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    write_metadata(root, query_file)

    output =
      File.cd!(root, fn ->
        capture_io(fn -> Mix.Task.run("squirrelix.gen", []) end)
      end)

    assert output =~ "Generated 1 query."

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~
             "defmodule AcornCounter.Accounts.SQL do"
  end

  test "mix squirrelix.check loads metadata and checks generated modules" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    write_metadata(root, query_file)

    File.cd!(root, fn ->
      capture_io(fn -> Mix.Task.run("squirrelix.gen", []) end)
      Mix.Task.reenable("squirrelix.check")

      output = capture_io(fn -> Mix.Task.run("squirrelix.check", []) end)

      assert output =~ "All 1 query current."
    end)
  end

  test "mix squirrelix.gen accepts a custom metadata file" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    metadata_file = Path.join(root, "config/squirr_elix.exs")
    write_metadata(root, query_file, metadata_file)

    output =
      File.cd!(root, fn ->
        capture_io(fn -> Mix.Task.run("squirrelix.gen", ["--metadata", metadata_file]) end)
      end)

    assert output =~ "Generated 1 query."
  end

  test "mix squirrelix.gen can infer metadata from Postgres" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")

    output =
      File.cd!(root, fn ->
        capture_io(fn ->
          Mix.Task.run("squirrelix.gen", ["--infer", "--database", "postgres"])
        end)
      end)

    assert output =~ "Generated 1 query."
    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "required(:name) => String.t()"
  end

  test "mix squirrelix.gen can infer metadata from a Postgres URL" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")

    output =
      File.cd!(root, fn ->
        capture_io(fn ->
          Mix.Task.run("squirrelix.gen", [
            "--infer",
            "--url",
            Squirrelix.TestSupport.postgres_url()
          ])
        end)
      end)

    assert output =~ "Generated 1 query."
    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "required(:name) => String.t()"
  end

  test "mix squirrelix.gen rejects invalid Postgres URLs" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")

    assert_raise Mix.Error, "Invalid Postgres connection URL", fn ->
      File.cd!(root, fn ->
        Mix.Task.run("squirrelix.gen", ["--infer", "--url", "mysql://localhost/postgres"])
      end)
    end
  end

  test "mix squirrelix.gen moduledoc documents metadata and infer options" do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(Mix.Tasks.Squirrelix.Gen)
    moduledoc = module_doc["en"]

    assert moduledoc =~ "--metadata"
    assert moduledoc =~ "--infer"
    assert moduledoc =~ "squirr_elix.exs"
  end

  test "mix squirrelix.check moduledoc documents usage" do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(Mix.Tasks.Squirrelix.Check)
    moduledoc = module_doc["en"]

    assert moduledoc =~ "mix squirrelix.check"
    assert moduledoc =~ "--infer"
  end

  defp tmp_project(app) do
    path = Squirrelix.TestSupport.tmp_dir!("squirr_elix-mix-task")

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
    metadata_file = metadata_file || Path.join(root, "squirr_elix.exs")
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
