defmodule SquirrelixWatchTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Squirrelix.Watch

  describe "sql_query_path?/2" do
    test "accepts .sql files directly under sql/ in source roots" do
      root = "/tmp/project"

      assert Watch.sql_query_path?("/tmp/project/lib/accounts/sql/find.sql", root)
      assert Watch.sql_query_path?("/tmp/project/test/support/sql/list.sql", root)
      assert Watch.sql_query_path?("/tmp/project/dev/sql/seed.sql", root)
    end

    test "accepts macOS /private-prefixed paths against /var roots" do
      root = "/var/folders/tmp/project"
      path = "/private/var/folders/tmp/project/lib/accounts/sql/find.sql"

      assert Watch.sql_query_path?(path, root)
    end

    test "rejects non-sql files and sql files outside sql/ directories" do
      root = "/tmp/project"

      refute Watch.sql_query_path?("/tmp/project/lib/accounts/sql.ex", root)
      refute Watch.sql_query_path?("/tmp/project/lib/accounts/find.sql", root)
      refute Watch.sql_query_path?("/tmp/project/lib/accounts/sql/nested/find.sql", root)
      refute Watch.sql_query_path?("/tmp/project/priv/sql/find.sql", root)
      refute Watch.sql_query_path?("/tmp/other/lib/accounts/sql/find.sql", root)
    end
  end

  describe "watch loop" do
    test "debounces rapid sql file events into a single regenerate" do
      root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-watch")
      sql_dir = Path.join(root, "lib/accounts/sql")
      File.mkdir_p!(sql_dir)
      query = Path.join(sql_dir, "find_account.sql")
      File.write!(query, "select 1")

      parent = self()
      counter = :counters.new(1, [])

      task =
        Task.async(fn ->
          capture_io(fn ->
            Watch.run_loop(%{
              root: root,
              debounce_ms: 50,
              watcher_pid: parent,
              timer: nil,
              on_change: fn ->
                :counters.add(counter, 1, 1)
                send(parent, :regenerated)
              end
            })
          end)
        end)

      send(task.pid, {:file_event, parent, {query, [:modified]}})
      send(task.pid, {:file_event, parent, {query, [:modified]}})
      send(task.pid, {:file_event, parent, {query, [:modified]}})

      assert_receive :regenerated, 500
      refute_receive :regenerated, 150
      assert :counters.get(counter, 1) == 1

      send(task.pid, :squirrelix_watch_stop)
      _ = Task.await(task)
    end

    test "ignores events for non-sql paths" do
      root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-watch")
      File.mkdir_p!(Path.join(root, "lib/accounts"))
      other = Path.join(root, "lib/accounts/sql.ex")
      File.write!(other, "defmodule X do\nend\n")

      parent = self()

      task =
        Task.async(fn ->
          capture_io(fn ->
            Watch.run_loop(%{
              root: root,
              debounce_ms: 20,
              watcher_pid: parent,
              timer: nil,
              on_change: fn -> send(parent, :regenerated) end
            })
          end)
        end)

      send(task.pid, {:file_event, parent, {other, [:modified]}})
      refute_receive :regenerated, 100

      send(task.pid, :squirrelix_watch_stop)
      _ = Task.await(task)
    end

    test "stops cleanly on stop message" do
      parent = self()

      task =
        Task.async(fn ->
          capture_io(fn ->
            result =
              Watch.run_loop(%{
                root: "/tmp",
                debounce_ms: 20,
                watcher_pid: parent,
                timer: nil,
                on_change: fn -> :ok end
              })

            send(parent, {:watch_result, result})
          end)
        end)

      send(task.pid, :squirrelix_watch_stop)
      assert_receive {:watch_result, :ok}, 500
      _ = Task.await(task)
    end

    test "stops cleanly on filesystem :stop event" do
      parent = self()

      task =
        Task.async(fn ->
          capture_io(fn ->
            result =
              Watch.run_loop(%{
                root: "/tmp",
                debounce_ms: 20,
                watcher_pid: parent,
                timer: nil,
                on_change: fn -> :ok end
              })

            send(parent, {:watch_result, result})
          end)
        end)

      send(task.pid, {:file_event, parent, :stop})
      assert_receive {:watch_result, :ok}, 500
      _ = Task.await(task)
    end
  end

  describe "watchable_dirs/1" do
    test "returns existing lib, test, and dev directories" do
      root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-watch-dirs")
      File.mkdir_p!(Path.join(root, "lib"))
      File.mkdir_p!(Path.join(root, "dev"))

      dirs = Watch.watchable_dirs(root)

      assert Path.join(root, "lib") in dirs
      assert Path.join(root, "dev") in dirs
      refute Path.join(root, "test") in dirs
    end
  end

  describe "watch!/1" do
    test "reports when there are no watchable directories" do
      root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-watch-empty")

      output =
        capture_io(:stderr, fn ->
          assert :ok = Watch.watch!(root: root, dirs: [], on_change: fn -> :ok end)
        end)

      assert output =~ "no lib/, test/, or dev/ directories"
      assert output =~ root
    end

    test "raises a clear error when the optional file_system dependency is missing" do
      root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-watch-no-fs")
      File.mkdir_p!(Path.join(root, "lib"))

      previous = Application.get_env(:squirr_elix, :file_system_available)

      try do
        Application.put_env(:squirr_elix, :file_system_available, false)

        error =
          assert_raise Mix.Error, fn ->
            Watch.watch!(root: root, on_change: fn -> :ok end)
          end

        message = Exception.message(error)
        assert message =~ "file_system"
        assert message =~ "--watch"
        assert message =~ ~r/mix deps\.get/i
      after
        if previous == nil do
          Application.delete_env(:squirr_elix, :file_system_available)
        else
          Application.put_env(:squirr_elix, :file_system_available, previous)
        end
      end
    end

    test "raises when FileSystem fails to start" do
      root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-watch-fs-error")
      File.mkdir_p!(Path.join(root, "lib"))

      name = :"squirr_elix_watch_fs_#{System.unique_integer([:positive])}"
      {:ok, _pid} = FileSystem.start_link(dirs: [Path.join(root, "lib")], name: name)

      previous = Application.get_env(:squirr_elix, :watch_filesystem_opts)

      try do
        Application.put_env(:squirr_elix, :watch_filesystem_opts, name: name)

        error =
          assert_raise Mix.Error, fn ->
            Watch.watch!(root: root, on_change: fn -> :ok end)
          end

        assert Exception.message(error) =~ "Could not start the file watcher"
        assert Exception.message(error) =~ "already_started"
      after
        if previous == nil do
          Application.delete_env(:squirr_elix, :watch_filesystem_opts)
        else
          Application.put_env(:squirr_elix, :watch_filesystem_opts, previous)
        end
      end
    end
  end
end
