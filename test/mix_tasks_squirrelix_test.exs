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

  test "mix squirrelix.gen can infer metadata from DATABASE_URL" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")
    previous = System.get_env("DATABASE_URL")

    try do
      System.put_env("DATABASE_URL", Squirrelix.TestSupport.postgres_url())

      output =
        File.cd!(root, fn ->
          capture_io(fn ->
            Mix.Task.run("squirrelix.gen", ["--infer"])
          end)
        end)

      assert output =~ "Generated 1 query."
      assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "required(:name) => String.t()"
    after
      restore_env("DATABASE_URL", previous)
    end
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

  test "mix squirrelix.gen rejects invalid DATABASE_URL" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")
    previous = System.get_env("DATABASE_URL")

    try do
      System.put_env("DATABASE_URL", "mysql://localhost/postgres")

      assert_raise Mix.Error, "Invalid Postgres connection URL", fn ->
        File.cd!(root, fn ->
          Mix.Task.run("squirrelix.gen", ["--infer"])
        end)
      end
    after
      restore_env("DATABASE_URL", previous)
    end
  end

  test "mix squirrelix.gen --infer reports structured connection refused errors" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")

    error =
      assert_raise Mix.Error, fn ->
        File.cd!(root, fn ->
          Mix.Task.run("squirrelix.gen", [
            "--infer",
            "--hostname",
            "127.0.0.1",
            "--port",
            "1",
            "--username",
            "postgres",
            "--database",
            "postgres"
          ])
        end)
      end

    message = Exception.message(error)
    assert message =~ "Cannot connect to Postgres"
    assert message =~ "`127.0.0.1`"
    assert message =~ "refused"
    assert message =~ "PGHOST"
    refute message =~ "%DBConnection.ConnectionError"
    refute message =~ "Could not connect to Postgres:"
  end

  test "mix squirrelix.gen --infer reports structured connection timeouts" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")

    error =
      assert_raise Mix.Error, fn ->
        File.cd!(root, fn ->
          Mix.Task.run("squirrelix.gen", [
            "--infer",
            "--url",
            "postgres://postgres@172.31.255.1:5432/postgres?connect_timeout=1"
          ])
        end)
      end

    message = Exception.message(error)
    assert message =~ "Connection timed out"
    assert message =~ "`172.31.255.1`"
    assert message =~ "PGCONNECT_TIMEOUT"
    refute message =~ "Could not connect to Postgres:"
  end

  test "mix squirrelix.gen --infer --write-metadata exports metadata for offline check" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")
    metadata_file = Path.join(root, "squirr_elix.exs")

    File.cd!(root, fn ->
      output =
        capture_io(fn ->
          Mix.Task.run("squirrelix.gen", [
            "--infer",
            "--database",
            "postgres",
            "--write-metadata",
            metadata_file
          ])
        end)

      assert output =~ "Generated 1 query."
      assert output =~ "Wrote metadata"
      assert File.exists?(metadata_file)

      Mix.Task.reenable("squirrelix.check")

      check_output =
        capture_io(fn ->
          Mix.Task.run("squirrelix.check", ["--metadata", metadata_file])
        end)

      assert check_output =~ "All 1 query current."
    end)
  end

  test "mix squirrelix.check detects drift after metadata export when generated output changes" do
    root = tmp_project(:acorn_counter)
    write_query(root, "select $1::text as name")
    metadata_file = Path.join(root, "config/squirr_elix.exs")

    File.cd!(root, fn ->
      capture_io(fn ->
        Mix.Task.run("squirrelix.gen", [
          "--infer",
          "--database",
          "postgres",
          "--write-metadata",
          metadata_file
        ])
      end)

      generated = Path.join(root, "lib/accounts/sql.ex")

      File.write!(
        generated,
        String.replace(File.read!(generated), "name", "renamed", global: false)
      )

      Mix.Task.reenable("squirrelix.check")

      error =
        assert_raise Mix.Error, fn ->
          Mix.Task.run("squirrelix.check", ["--metadata", metadata_file])
        end

      assert Exception.message(error) =~ "Squirrelix check failed"
      assert Exception.message(error) =~ "Outdated"
    end)
  end

  test "mix squirrelix.gen rejects --write-metadata without --infer" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    write_metadata(root, query_file)

    assert_raise Mix.Error, ~r/--write-metadata requires --infer/, fn ->
      File.cd!(root, fn ->
        Mix.Task.run("squirrelix.gen", ["--write-metadata", "squirr_elix.exs"])
      end)
    end
  end

  test "mix squirrelix.gen moduledoc documents metadata and infer options" do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(Mix.Tasks.Squirrelix.Gen)
    moduledoc = module_doc["en"]

    assert moduledoc =~ "--metadata"
    assert moduledoc =~ "--infer"
    assert moduledoc =~ "--write-metadata"
    assert moduledoc =~ "--watch"
    assert moduledoc =~ "squirr_elix.exs"
    assert moduledoc =~ "DATABASE_URL"
    assert moduledoc =~ "sslmode"
    assert moduledoc =~ "flags → `--url` → `DATABASE_URL` → `PG*` → defaults"
  end

  test "mix squirrelix.check moduledoc documents usage" do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(Mix.Tasks.Squirrelix.Check)
    moduledoc = module_doc["en"]

    assert moduledoc =~ "mix squirrelix.check"
    assert moduledoc =~ "--infer"
    assert moduledoc =~ "--write-metadata"
    assert moduledoc =~ "DATABASE_URL"
  end

  test "mix squirrelix.gen --watch regenerates when a sql file changes" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root, "-- Find account\nselect name from accounts where id = $1")
    write_metadata(root, query_file)
    parent = self()

    previous_debounce = Application.get_env(:squirr_elix, :watch_debounce_ms)
    previous_hook = Application.get_env(:squirr_elix, :watch_test_hook)

    try do
      Application.put_env(:squirr_elix, :watch_debounce_ms, 50)

      Application.put_env(:squirr_elix, :watch_test_hook, fn watch_pid ->
        send(parent, {:watch_ready, watch_pid})
      end)

      task =
        Task.async(fn ->
          File.cd!(root, fn ->
            capture_io(fn -> Mix.Task.run("squirrelix.gen", ["--watch"]) end)
          end)
        end)

      assert_receive {:watch_ready, watch_pid}, 5_000
      # Allow the native FileSystem backend to finish subscribing.
      Process.sleep(100)

      generated = Path.join(root, "lib/accounts/sql.ex")
      assert File.exists?(generated)
      refute File.read!(generated) =~ "Regenerated by watch"

      File.write!(
        query_file,
        "-- Regenerated by watch\nselect name from accounts where id = $1"
      )

      assert wait_until(fn -> File.read!(generated) =~ "Regenerated by watch" end, 80)

      send(watch_pid, :squirrelix_watch_stop)
      assert Task.await(task, 5_000)
    after
      restore_app_env(:watch_debounce_ms, previous_debounce)
      restore_app_env(:watch_test_hook, previous_hook)
    end
  end

  test "mix squirrelix.gen --watch keeps running after regenerate failures" do
    root = tmp_project(:acorn_counter)
    query_file = write_query(root)
    write_metadata(root, query_file)
    parent = self()

    previous_debounce = Application.get_env(:squirr_elix, :watch_debounce_ms)
    previous_hook = Application.get_env(:squirr_elix, :watch_test_hook)

    try do
      Application.put_env(:squirr_elix, :watch_debounce_ms, 50)

      Application.put_env(:squirr_elix, :watch_test_hook, fn watch_pid ->
        send(parent, {:watch_ready, watch_pid})
      end)

      task =
        Task.async(fn ->
          File.cd!(root, fn ->
            capture_io(fn ->
              capture_io(:stderr, fn ->
                Mix.Task.run("squirrelix.gen", ["--watch"])
              end)
            end)
          end)
        end)

      assert_receive {:watch_ready, watch_pid}, 5_000
      Process.sleep(100)

      File.write!(Path.join(root, "squirr_elix.exs"), "%{}\n")
      File.write!(query_file, "-- trigger\nselect name from accounts where id = $1")

      Process.sleep(250)
      assert Process.alive?(watch_pid)

      send(watch_pid, :squirrelix_watch_stop)
      assert Task.await(task, 5_000)
    after
      restore_app_env(:watch_debounce_ms, previous_debounce)
      restore_app_env(:watch_test_hook, previous_hook)
    end
  end

  test "mix squirrelix.check rejects --watch" do
    assert_raise Mix.Error, ~r/--watch/, fn ->
      Mix.Task.run("squirrelix.check", ["--watch"])
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp restore_app_env(key, nil), do: Application.delete_env(:squirr_elix, key)
  defp restore_app_env(key, value), do: Application.put_env(:squirr_elix, key, value)

  defp wait_until(fun, attempts) when is_integer(attempts) and attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(50)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: false

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
