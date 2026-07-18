defmodule SquirrelixirCliCompatibilityTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.CLI
  alias Squirrelixir.ConnectionOptions

  test "parse_connection_url accepts postgres and postgresql schemes" do
    assert {:ok,
            %ConnectionOptions{
              host: "db",
              port: 5433,
              user: "user",
              password: "pass",
              database: "my_db",
              timeout_seconds: 11
            }} =
             CLI.parse_connection_url("postgres://user:pass@db:5433/my_db?connect_timeout=11")

    assert {:ok,
            %ConnectionOptions{
              host: "db",
              port: 5433,
              user: "user",
              password: "pass",
              database: "my_db",
              timeout_seconds: 11
            }} =
             CLI.parse_connection_url("postgresql://user:pass@db:5433/my_db?connect_timeout=11")
  end

  test "parse_connection_url rejects unknown scheme" do
    assert :error = CLI.parse_connection_url("mysql://user:pass@db:3306/my_db")
  end

  test "parse_connection_url applies upstream defaults" do
    assert {:ok,
            %ConnectionOptions{
              host: "localhost",
              port: 5432,
              user: "postgres",
              password: "",
              database: "database",
              timeout_seconds: 5
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
               timeout_seconds: 8
             }
  end

  test "connection_options_from_variables falls back to project name then default" do
    assert CLI.connection_options_from_variables(%{}, "squirrelixir") ==
             %ConnectionOptions{
               host: "localhost",
               port: 5432,
               user: "postgres",
               password: "",
               database: "squirrelixir",
               timeout_seconds: 5
             }

    assert CLI.connection_options_from_variables(%{}, nil) ==
             %ConnectionOptions{
               host: "localhost",
               port: 5432,
               user: "postgres",
               password: "",
               database: "database",
               timeout_seconds: 5
             }
  end

  test "walk finds only sql directories and sql files" do
    tmp =
      Path.join(System.tmp_dir!(), "squirrelixir-#{System.unique_integer([:positive])}")

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

    assert CLI.walk(Path.join(tmp, "src")) == expected
  end

  test "directory_to_output_file maps sql directory to sibling sql.ex" do
    assert CLI.directory_to_output_file("/tmp/my_app/src/admin/sql") ==
             "/tmp/my_app/src/admin/sql.ex"
  end
end
