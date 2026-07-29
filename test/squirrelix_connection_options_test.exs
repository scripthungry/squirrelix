defmodule SquirrelixConnectionOptionsTest do
  use ExUnit.Case, async: true

  alias Squirrelix.CLI
  alias Squirrelix.ConnectionOptions
  alias Squirrelix.Postgres

  describe "parse_connection_url/1 sslmode" do
    test "parses sslmode=disable as ssl: false" do
      assert {:ok, %ConnectionOptions{ssl: false}} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=disable")
    end

    test "parses sslmode=require into encrypting Postgrex ssl opts" do
      assert {:ok, %ConnectionOptions{ssl: ssl}} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=require")

      assert ssl in [true, [verify: :verify_none]] or
               (is_list(ssl) and Keyword.get(ssl, :verify) == :verify_none)
    end

    test "parses sslmode=verify-full as ssl: true (secure defaults)" do
      assert {:ok, %ConnectionOptions{ssl: true}} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=verify-full")
    end

    test "parses sslmode=verify-ca as ssl: true (secure defaults)" do
      assert {:ok, %ConnectionOptions{ssl: true}} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=verify-ca")
    end

    test "parses ssl=true like require" do
      assert {:ok, %ConnectionOptions{ssl: ssl}} =
               CLI.parse_connection_url("postgres://u@h/db?ssl=true")

      assert ssl in [true, [verify: :verify_none]] or
               (is_list(ssl) and Keyword.get(ssl, :verify) == :verify_none)
    end

    test "parses ssl=false as ssl: false" do
      assert {:ok, %ConnectionOptions{ssl: false}} =
               CLI.parse_connection_url("postgres://u@h/db?ssl=false")
    end

    test "parses sslmode=allow and prefer as ssl: false" do
      assert {:ok, %ConnectionOptions{ssl: false}} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=allow")

      assert {:ok, %ConnectionOptions{ssl: false}} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=prefer")
    end

    test "rejects invalid connect_timeout and ssl query values" do
      assert {:error, :invalid_url} =
               CLI.parse_connection_url("postgres://u@h/db?connect_timeout=abc")

      assert {:error, :invalid_url} =
               CLI.parse_connection_url("postgres://u@h/db?ssl=maybe")
    end

    test "leaves ssl unset for empty sslmode" do
      assert {:ok, %ConnectionOptions{ssl: nil}} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=")
    end

    test "rejects unknown sslmode" do
      assert {:error, :invalid_url} =
               CLI.parse_connection_url("postgres://u@h/db?sslmode=nonsense")
    end

    test "leaves ssl unset when query has no ssl params" do
      assert {:ok, %ConnectionOptions{ssl: nil}} =
               CLI.parse_connection_url("postgres://u:p@h:5432/db?connect_timeout=3")
    end
  end

  describe "resolve_connection_options/2 precedence" do
    test "uses DATABASE_URL when no --url or flags" do
      env = %{
        "DATABASE_URL" => "postgres://url_user:url_pass@urlhost:6543/url_db?connect_timeout=9",
        "PGHOST" => "pghost",
        "PGUSER" => "pguser",
        "PGPASSWORD" => "pgpass",
        "PGDATABASE" => "pgdb",
        "PGPORT" => "5432"
      }

      assert {:ok,
              %ConnectionOptions{
                host: "urlhost",
                port: 6543,
                user: "url_user",
                password: "url_pass",
                database: "url_db",
                timeout_seconds: 9
              }} = CLI.resolve_connection_options(env, [])
    end

    test "prefers --url over DATABASE_URL" do
      env = %{
        "DATABASE_URL" => "postgres://from_env@envhost/env_db"
      }

      assert {:ok, %ConnectionOptions{host: "flaghost", database: "flag_db", user: "from_flag"}} =
               CLI.resolve_connection_options(env,
                 url: "postgres://from_flag@flaghost/flag_db"
               )
    end

    test "prefers CLI flags over --url and DATABASE_URL" do
      env = %{"DATABASE_URL" => "postgres://env@envhost/env_db"}

      assert {:ok,
              %ConnectionOptions{
                host: "cli-host",
                database: "cli_db",
                user: "cli_user",
                port: 5555
              }} =
               CLI.resolve_connection_options(env,
                 url: "postgres://url@urlhost/url_db",
                 hostname: "cli-host",
                 database: "cli_db",
                 username: "cli_user",
                 port: 5555
               )
    end

    test "falls back to PG* when DATABASE_URL is unset" do
      env = %{
        "PGHOST" => "localhost",
        "PGPORT" => "6543",
        "PGUSER" => "alice",
        "PGPASSWORD" => "secret",
        "PGDATABASE" => "app_db",
        "PGCONNECT_TIMEOUT" => "8"
      }

      assert {:ok,
              %ConnectionOptions{
                host: "localhost",
                port: 6543,
                user: "alice",
                password: "secret",
                database: "app_db",
                timeout_seconds: 8,
                ssl: false
              }} = CLI.resolve_connection_options(env, [])
    end

    test "honors PGSSLMODE when no URL sslmode" do
      env = %{
        "PGHOST" => "localhost",
        "PGSSLMODE" => "require"
      }

      assert {:ok, %ConnectionOptions{ssl: ssl}} = CLI.resolve_connection_options(env, [])

      assert ssl in [true, [verify: :verify_none]] or
               (is_list(ssl) and Keyword.get(ssl, :verify) == :verify_none)
    end

    test "URL sslmode overrides PGSSLMODE" do
      env = %{
        "DATABASE_URL" => "postgres://u@h/db?sslmode=disable",
        "PGSSLMODE" => "require"
      }

      assert {:ok, %ConnectionOptions{ssl: false}} = CLI.resolve_connection_options(env, [])
    end

    test "returns error for invalid DATABASE_URL" do
      env = %{"DATABASE_URL" => "mysql://u@h/db"}

      assert {:error, :invalid_url} = CLI.resolve_connection_options(env, [])
    end

    test "empty password in URL does not wipe PGPASSWORD" do
      env = %{
        "DATABASE_URL" => "postgres://user@host/db",
        "PGPASSWORD" => "from_env"
      }

      assert {:ok, %ConnectionOptions{password: "from_env"}} =
               CLI.resolve_connection_options(env, [])
    end

    test "explicit empty password in URL does not wipe PGPASSWORD" do
      env = %{
        "DATABASE_URL" => "postgres://user:@host/db",
        "PGPASSWORD" => "from_env"
      }

      assert {:ok, %ConnectionOptions{password: "from_env"}} =
               CLI.resolve_connection_options(env, [])
    end

    test "invalid PGSSLMODE falls back to false" do
      env = %{"PGHOST" => "localhost", "PGSSLMODE" => "nonsense"}

      assert {:ok, %ConnectionOptions{ssl: false}} = CLI.resolve_connection_options(env, [])
    end

    test "invalid PGPORT falls back to default" do
      env = %{"PGHOST" => "localhost", "PGPORT" => "nope"}

      assert {:ok, %ConnectionOptions{port: 5432}} = CLI.resolve_connection_options(env, [])
    end

    test "percent-decodes userinfo in DATABASE_URL" do
      env = %{
        "DATABASE_URL" => "postgres://u%40mail:p%40ss%3Aword@dbhost:5432/app_db"
      }

      assert {:ok,
              %ConnectionOptions{
                user: "u@mail",
                password: "p@ss:word",
                host: "dbhost",
                database: "app_db"
              }} = CLI.resolve_connection_options(env, [])
    end

    test "rejects schemeless garbage URLs" do
      assert {:error, :invalid_url} =
               CLI.resolve_connection_options(%{"DATABASE_URL" => "localhost:5432/db"}, [])

      assert {:error, :invalid_url} =
               CLI.parse_connection_url("user:pass@host/db")
    end

    test "URL defaults do not clobber present PG* values for partial URLs" do
      env = %{
        "DATABASE_URL" => "postgres://url_user@urlhost/",
        "PGDATABASE" => "from_pg",
        "PGPASSWORD" => "from_pg_pass",
        "PGPORT" => "6543",
        "PGCONNECT_TIMEOUT" => "12"
      }

      assert {:ok,
              %ConnectionOptions{
                user: "url_user",
                host: "urlhost",
                database: "from_pg",
                password: "from_pg_pass",
                port: 6543,
                timeout_seconds: 12
              }} = CLI.resolve_connection_options(env, [])
    end

    test "partial URL without host keeps PGHOST" do
      env = %{
        "DATABASE_URL" => "postgres://only_user@/only_db",
        "PGHOST" => "pg_host",
        "PGPORT" => "6000"
      }

      assert {:ok,
              %ConnectionOptions{
                user: "only_user",
                database: "only_db",
                host: "pg_host",
                port: 6000
              }} = CLI.resolve_connection_options(env, [])
    end
  end

  describe "Postgres.postgrex_opts/1 SSL wiring" do
    test "includes ssl: false when disabled" do
      opts =
        Postgres.postgrex_opts(%ConnectionOptions{
          host: "localhost",
          port: 5432,
          user: "postgres",
          password: "",
          database: "postgres",
          timeout_seconds: 5,
          ssl: false
        })

      assert Keyword.get(opts, :ssl) == false
    end

    test "includes ssl opts when require-style SSL is set" do
      opts =
        Postgres.postgrex_opts(%ConnectionOptions{
          host: "db.example.com",
          port: 5432,
          user: "postgres",
          password: "secret",
          database: "app",
          timeout_seconds: 5,
          ssl: [verify: :verify_none]
        })

      assert Keyword.get(opts, :ssl) == [verify: :verify_none]
    end

    test "includes ssl: true for verify modes" do
      opts =
        Postgres.postgrex_opts(%ConnectionOptions{
          host: "db.example.com",
          port: 5432,
          user: "postgres",
          password: "secret",
          database: "app",
          timeout_seconds: 5,
          ssl: true
        })

      assert Keyword.get(opts, :ssl) == true
    end
  end
end
