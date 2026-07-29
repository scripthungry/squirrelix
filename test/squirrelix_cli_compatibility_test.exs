defmodule SquirrelixCliCompatibilityTest do
  use ExUnit.Case, async: true

  alias Squirrelix.CLI
  alias Squirrelix.ConnectionOptions
  alias Squirrelix.Query
  alias Squirrelix.QueryDirectory

  test "parse_connection_url accepts postgres and postgresql schemes" do
    assert {:ok,
            %ConnectionOptions{
              host: "db",
              port: 5433,
              user: "user",
              password: "pass",
              database: "my_db",
              timeout_seconds: 11,
              ssl: nil
            }} =
             CLI.parse_connection_url("postgres://user:pass@db:5433/my_db?connect_timeout=11")

    assert {:ok,
            %ConnectionOptions{
              host: "db",
              port: 5433,
              user: "user",
              password: "pass",
              database: "my_db",
              timeout_seconds: 11,
              ssl: nil
            }} =
             CLI.parse_connection_url("postgresql://user:pass@db:5433/my_db?connect_timeout=11")
  end

  test "parse_connection_url rejects unknown scheme" do
    assert {:error, :invalid_url} =
             CLI.parse_connection_url("mysql://user:pass@db:3306/my_db")
  end

  test "parse_connection_url rejects schemeless URLs" do
    assert {:error, :invalid_url} = CLI.parse_connection_url("localhost:5432/db")
    assert {:error, :invalid_url} = CLI.parse_connection_url("user:pass@host/db")
  end

  test "parse_connection_url percent-decodes userinfo" do
    assert {:ok, %ConnectionOptions{user: "u@mail", password: "p@ss"}} =
             CLI.parse_connection_url("postgres://u%40mail:p%40ss@db/my_db")
  end

  test "parse_connection_url applies upstream defaults" do
    assert {:ok,
            %ConnectionOptions{
              host: "localhost",
              port: 5432,
              user: "postgres",
              password: "",
              database: "database",
              timeout_seconds: 5,
              ssl: nil
            }} = CLI.parse_connection_url("postgres://")
  end

  test "connection_options_from_variables reads environment and defaults" do
    env = %{
      "PGHOST" => "localhost",
      "PGPORT" => "6543",
      "PGUSER" => "alice",
      "PGPASSWORD" => "secret",
      "PGDATABASE" => "app_db",
      "PGCONNECT_TIMEOUT" => "8"
    }

    assert CLI.connection_options_from_variables(env, "fallback_db") ==
             %ConnectionOptions{
               host: "localhost",
               port: 6543,
               user: "alice",
               password: "secret",
               database: "app_db",
               timeout_seconds: 8,
               ssl: false
             }
  end

  test "connection_options_from_variables falls back to project name then default" do
    assert CLI.connection_options_from_variables(%{}, "squirr_elix") ==
             %ConnectionOptions{
               host: "localhost",
               port: 5432,
               user: "postgres",
               password: "",
               database: "squirr_elix",
               timeout_seconds: 5,
               ssl: false
             }

    assert CLI.connection_options_from_variables(%{}, nil) ==
             %ConnectionOptions{
               host: "localhost",
               port: 5432,
               user: "postgres",
               password: "",
               database: "database",
               timeout_seconds: 5,
               ssl: false
             }
  end

  test "discover_sql_directories finds only sql directories and sql files" do
    tmp = tmp_dir("squirr_elix")

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

    assert CLI.discover_sql_directories(Path.join(tmp, "src")) == {:ok, expected}
  end

  test "discover_sql_directories returns CannotReadFile when a directory is unreadable" do
    tmp = tmp_dir("squirr_elix-unreadable")
    blocked = Path.join(tmp, "blocked")
    File.mkdir_p!(blocked)
    File.write!(Path.join(blocked, "note.txt"), "x")

    # Remove execute permission so File.ls/1 fails with eacces on Unix.
    File.chmod!(blocked, 0o000)

    try do
      assert {:error, %Squirrelix.Error.CannotReadFile{file: ^blocked, reason: reason}} =
               CLI.discover_sql_directories(tmp)

      assert reason in [:eacces, :enotdir]
    after
      File.chmod!(blocked, 0o755)
    end
  end

  test "query_files discovers sql files under conventional Elixir project roots" do
    tmp = tmp_dir("squirr_elix-cli")

    File.mkdir_p!(Path.join(tmp, "lib/accounts/sql"))
    File.mkdir_p!(Path.join(tmp, "test/support/sql"))
    File.mkdir_p!(Path.join(tmp, "dev/scratch/sql"))
    File.mkdir_p!(Path.join(tmp, "priv/sql"))
    File.write!(Path.join(tmp, "mix.exs"), "defmodule Temp.MixProject do\nend\n")
    File.write!(Path.join(tmp, "lib/accounts/sql/find_user.sql"), "select 1")
    File.write!(Path.join(tmp, "test/support/sql/test_query.sql"), "select 2")
    File.write!(Path.join(tmp, "dev/scratch/sql/dev_query.sql"), "select 3")
    File.write!(Path.join(tmp, "priv/sql/ignored.sql"), "select 4")

    assert CLI.query_files(tmp) ==
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
    tmp = tmp_dir("squirr_elix-cli")

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
            ]} = CLI.query_directories(tmp)
  end

  test "query_files and query_directories propagate discover errors" do
    tmp = tmp_dir("squirr_elix-cli-unreadable")
    blocked = Path.join(tmp, "lib")
    File.mkdir_p!(blocked)
    File.write!(Path.join(tmp, "mix.exs"), "defmodule Temp.MixProject do\nend\n")
    File.chmod!(blocked, 0o000)

    try do
      assert {:error, %Squirrelix.Error.CannotReadFile{file: ^blocked}} = CLI.query_files(tmp)

      assert {:error, %Squirrelix.Error.CannotReadFile{file: ^blocked}} =
               CLI.query_directories(tmp)
    after
      File.chmod!(blocked, 0o755)
    end
  end

  test "discover_sql_directories treats a missing sql basename as empty" do
    missing = Path.join(tmp_dir("squirr_elix-missing-sql"), "sql")

    assert CLI.discover_sql_directories(missing) == {:ok, %{}}
  end

  test "directory_to_output_file maps sql directory to sibling sql.ex" do
    assert CLI.directory_to_output_file("/tmp/my_app/src/admin/sql") ==
             "/tmp/my_app/src/admin/sql.ex"
  end

  defp tmp_dir(prefix) do
    Squirrelix.TestSupport.tmp_dir!(prefix)
  end
end
