defmodule SquirrelixCliCompatibilityTest do
  use ExUnit.Case, async: true

  alias Squirrelix.CLI
  alias Squirrelix.ConnectionOptions

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
end
