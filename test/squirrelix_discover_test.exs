defmodule SquirrelixDiscoverTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Discover
  alias Squirrelix.Query
  alias Squirrelix.QueryDirectory

  test "discover_sql_directories finds only sql directories and sql files" do
    tmp = tmp_dir("squirr_elix-discover")

    File.mkdir_p!(tmp)

    File.mkdir_p!(Path.join(tmp, "src/feature/sql"))
    File.write!(Path.join(tmp, "src/feature/sql/one.sql"), "select 1")
    File.write!(Path.join(tmp, "src/feature/sql/two.sql"), "select 2")
    File.write!(Path.join(tmp, "src/feature/sql/ignore.txt"), "ignore")
    File.mkdir_p!(Path.join(tmp, "src/feature/not_sql"))
    File.write!(Path.join(tmp, "src/feature/not_sql/three.sql"), "select 3")

    expected = %{
      Path.join(tmp, "src/feature/sql") => [
        Path.join(tmp, "src/feature/sql/one.sql"),
        Path.join(tmp, "src/feature/sql/two.sql")
      ]
    }

    assert Discover.discover_sql_directories(Path.join(tmp, "src")) == {:ok, expected}
  end

  test "discover_sql_directories returns CannotReadFile when a directory is unreadable" do
    tmp = tmp_dir("squirr_elix-discover-unreadable")
    blocked = Path.join(tmp, "blocked")
    File.mkdir_p!(blocked)
    File.write!(Path.join(blocked, "note.txt"), "x")

    # Remove execute permission so File.ls/1 fails with eacces on Unix.
    File.chmod!(blocked, 0o000)

    try do
      assert {:error, %Squirrelix.Error.CannotReadFile{file: ^blocked, reason: reason}} =
               Discover.discover_sql_directories(tmp)

      assert reason in [:eacces, :enotdir]
    after
      File.chmod!(blocked, 0o755)
    end
  end

  test "query_files discovers sql files under conventional Elixir project roots" do
    tmp = tmp_dir("squirr_elix-discover-roots")

    File.mkdir_p!(Path.join(tmp, "lib/accounts/sql"))
    File.mkdir_p!(Path.join(tmp, "test/support/sql"))
    File.mkdir_p!(Path.join(tmp, "dev/scratch/sql"))
    File.mkdir_p!(Path.join(tmp, "priv/sql"))
    File.write!(Path.join(tmp, "mix.exs"), "defmodule Temp.MixProject do\nend\n")
    File.write!(Path.join(tmp, "lib/accounts/sql/find_user.sql"), "select 1")
    File.write!(Path.join(tmp, "test/support/sql/test_query.sql"), "select 2")
    File.write!(Path.join(tmp, "dev/scratch/sql/dev_query.sql"), "select 3")
    File.write!(Path.join(tmp, "priv/sql/ignored.sql"), "select 4")

    assert Discover.query_files(tmp) ==
             {:ok,
              %{
                Path.join(tmp, "dev/scratch/sql") => [
                  Path.join(tmp, "dev/scratch/sql/dev_query.sql")
                ],
                Path.join(tmp, "lib/accounts/sql") => [
                  Path.join(tmp, "lib/accounts/sql/find_user.sql")
                ],
                Path.join(tmp, "test/support/sql") => [
                  Path.join(tmp, "test/support/sql/test_query.sql")
                ]
              }}
  end

  test "query_directories loads discovered SQL files into query directories" do
    tmp = tmp_dir("squirr_elix-discover-dirs")

    File.mkdir_p!(Path.join(tmp, "lib/accounts/sql"))
    File.write!(Path.join(tmp, "mix.exs"), "defmodule Temp.MixProject do\nend\n")
    File.write!(Path.join(tmp, "lib/accounts/sql/find_user.sql"), "select 1")

    accounts_dir = Path.join(tmp, "lib/accounts/sql")

    assert {:ok,
            [
              %QueryDirectory{
                directory: ^accounts_dir,
                queries: [%Query{name: "find_user", content: "select 1"}],
                errors: []
              }
            ]} = Discover.query_directories(tmp)
  end

  test "query_files and query_directories propagate discover errors" do
    tmp = tmp_dir("squirr_elix-discover-propagate")
    blocked = Path.join(tmp, "lib")
    File.mkdir_p!(blocked)
    File.write!(Path.join(tmp, "mix.exs"), "defmodule Temp.MixProject do\nend\n")
    File.chmod!(blocked, 0o000)

    try do
      assert {:error, %Squirrelix.Error.CannotReadFile{file: ^blocked}} =
               Discover.query_files(tmp)

      assert {:error, %Squirrelix.Error.CannotReadFile{file: ^blocked}} =
               Discover.query_directories(tmp)
    after
      File.chmod!(blocked, 0o755)
    end
  end

  test "discover_sql_directories treats a missing sql basename as empty" do
    missing = Path.join(tmp_dir("squirr_elix-discover-missing-sql"), "sql")

    assert Discover.discover_sql_directories(missing) == {:ok, %{}}
  end

  test "directory_to_output_file maps sql directory to sibling sql.ex" do
    assert Discover.directory_to_output_file("/tmp/my_app/src/admin/sql") ==
             "/tmp/my_app/src/admin/sql.ex"
  end

  defp tmp_dir(prefix) do
    Squirrelix.TestSupport.tmp_dir!(prefix)
  end
end
