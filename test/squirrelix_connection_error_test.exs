defmodule SquirrelixConnectionErrorTest do
  use ExUnit.Case, async: true

  alias Squirrelix.ConnectionOptions
  alias Squirrelix.Error
  alias Squirrelix.Error.CannotConnectToPostgres
  alias Squirrelix.Error.PostgresConnectionTimeout

  describe "Error.connection_error/2" do
    test "classifies TCP connection refused" do
      opts = connection_options()

      error =
        Error.connection_error(
          %DBConnection.ConnectionError{
            message: "tcp connect (127.0.0.1:1): connection refused - :econnrefused",
            reason: :error
          },
          opts
        )

      assert %CannotConnectToPostgres{
               host: "127.0.0.1",
               port: 1,
               reason: :refused,
               user: "postgres",
               database: "postgres"
             } = error
    end

    test "classifies TCP connection timeout as a dedicated timeout error" do
      opts = connection_options(host: "172.31.255.1", port: 5432, timeout_seconds: 2)

      error =
        Error.connection_error(
          %DBConnection.ConnectionError{
            message: "tcp connect (172.31.255.1:5432): timeout",
            reason: :error
          },
          opts
        )

      assert %PostgresConnectionTimeout{
               host: "172.31.255.1",
               port: 5432,
               timeout_seconds: 2
             } = error
    end

    test "classifies invalid authorization / missing role" do
      opts = connection_options(user: "no_such_user")

      error =
        Error.connection_error(
          %Postgrex.Error{
            postgres: %{
              code: :invalid_authorization_specification,
              message: "role \"no_such_user\" does not exist"
            }
          },
          opts
        )

      assert %CannotConnectToPostgres{
               reason: :invalid_authorization,
               user: "no_such_user",
               message: "role \"no_such_user\" does not exist"
             } = error
    end

    test "classifies invalid password" do
      opts = connection_options(user: "alice")

      error =
        Error.connection_error(
          %Postgrex.Error{
            postgres: %{
              code: :invalid_password,
              message: "password authentication failed for user \"alice\""
            }
          },
          opts
        )

      assert %CannotConnectToPostgres{reason: :invalid_password, user: "alice"} = error
    end

    test "classifies missing database catalog" do
      opts = connection_options(database: "missing_db")

      error =
        Error.connection_error(
          %Postgrex.Error{
            postgres: %{
              code: :invalid_catalog_name,
              message: "database \"missing_db\" does not exist"
            }
          },
          opts
        )

      assert %CannotConnectToPostgres{
               reason: :invalid_catalog,
               database: "missing_db",
               message: "database \"missing_db\" does not exist"
             } = error
    end

    test "classifies unreachable, nxdomain, closed, and unknown TCP messages" do
      opts = connection_options()

      assert %CannotConnectToPostgres{reason: :unreachable} =
               Error.connection_error(
                 %DBConnection.ConnectionError{
                   message: "tcp connect: network is unreachable - :ehostunreach",
                   reason: :error
                 },
                 opts
               )

      assert %CannotConnectToPostgres{reason: :nxdomain} =
               Error.connection_error(
                 %DBConnection.ConnectionError{
                   message: "tcp connect (missing.example): non-existing domain - :nxdomain",
                   reason: :error
                 },
                 opts
               )

      assert %CannotConnectToPostgres{reason: :closed} =
               Error.connection_error(
                 %DBConnection.ConnectionError{
                   message: "tcp connect (127.0.0.1:5432): closed",
                   reason: :error
                 },
                 opts
               )

      assert %CannotConnectToPostgres{reason: :unknown, detail: detail} =
               Error.connection_error(
                 %DBConnection.ConnectionError{
                   message: "tcp connect: something unexpected",
                   reason: :error
                 },
                 opts
               )

      assert detail =~ "unexpected"
    end

    test "classifies atom connection reasons" do
      opts = connection_options()

      assert %PostgresConnectionTimeout{} = Error.connection_error(:timeout, opts)

      assert %CannotConnectToPostgres{reason: :refused} =
               Error.connection_error(:econnrefused, opts)

      assert %CannotConnectToPostgres{reason: :unreachable} =
               Error.connection_error(:ehostunreach, opts)

      assert %CannotConnectToPostgres{reason: :nxdomain} = Error.connection_error(:nxdomain, opts)
      assert %CannotConnectToPostgres{reason: :closed} = Error.connection_error(:closed, opts)

      assert %CannotConnectToPostgres{reason: :unknown, detail: :weird} =
               Error.connection_error(:weird, opts)
    end

    test "classifies unknown Postgrex codes as unknown connection errors" do
      opts = connection_options()

      assert %CannotConnectToPostgres{reason: :unknown} =
               Error.connection_error(
                 %Postgrex.Error{postgres: %{code: :too_many_connections, message: "busy"}},
                 opts
               )
    end
  end

  describe "Error.format/1 for connection failures" do
    test "formats connection refused with host/port and actionable hints" do
      formatted =
        Error.format(%CannotConnectToPostgres{
          host: "db.example.com",
          port: 5433,
          user: "app",
          database: "my_app",
          reason: :refused
        })

      assert formatted =~ "Error: Cannot connect to Postgres"
      assert formatted =~ "`db.example.com`"
      assert formatted =~ "5433"
      assert formatted =~ "refused"
      assert formatted =~ "PGHOST"
      assert formatted =~ "PGPORT"
      assert formatted =~ "squirr_elix.exs"
      refute formatted =~ "%DBConnection.ConnectionError"
      refute formatted =~ "tcp connect ("
    end

    test "formats connection timeout distinctly from other failures" do
      formatted =
        Error.format(%PostgresConnectionTimeout{
          host: "db.example.com",
          port: 5432,
          timeout_seconds: 5
        })

      assert formatted =~ "Error: Connection timed out"
      assert formatted =~ "`db.example.com`"
      assert formatted =~ "5432"
      assert formatted =~ "5"
      assert formatted =~ "PGCONNECT_TIMEOUT"
      assert formatted =~ "connect_timeout"
      assert formatted =~ "squirr_elix.exs"
      refute formatted =~ "Cannot connect to Postgres"
    end

    test "formats invalid authorization with credential hints" do
      formatted =
        Error.format(%CannotConnectToPostgres{
          host: "localhost",
          port: 5432,
          user: "app",
          database: "my_app",
          reason: :invalid_authorization,
          message: "role \"app\" does not exist"
        })

      assert formatted =~ "Error: Cannot authenticate with Postgres"
      assert formatted =~ "`app`"
      assert formatted =~ "`my_app`"
      assert formatted =~ "role \"app\" does not exist"
      assert formatted =~ "PGUSER"
      assert formatted =~ "PGDATABASE"
      assert formatted =~ "PGPASSWORD"
    end

    test "formats invalid password with PGPASSWORD hint" do
      formatted =
        Error.format(%CannotConnectToPostgres{
          host: "localhost",
          port: 5432,
          user: "alice",
          database: "postgres",
          reason: :invalid_password
        })

      assert formatted =~ "Error: Cannot authenticate with Postgres"
      assert formatted =~ "`alice`"
      assert formatted =~ "PGPASSWORD"
    end

    test "formats missing database with PGDATABASE hint" do
      formatted =
        Error.format(%CannotConnectToPostgres{
          host: "localhost",
          port: 5432,
          user: "postgres",
          database: "missing_db",
          reason: :invalid_catalog,
          message: "database \"missing_db\" does not exist"
        })

      assert formatted =~ "Error: Cannot connect to Postgres"
      assert formatted =~ "`missing_db`"
      assert formatted =~ "PGDATABASE"
    end

    test "formats missing database without an extra message line" do
      formatted =
        Error.format(%CannotConnectToPostgres{
          host: "localhost",
          port: 5432,
          user: "postgres",
          database: "missing_db",
          reason: :invalid_catalog,
          message: nil
        })

      assert formatted =~ "`missing_db`"
      assert formatted =~ "PGDATABASE"
      refute formatted =~ "does not exist"
    end

    test "formats closed, unreachable, nxdomain, and unknown TCP failures" do
      closed =
        Error.format(%CannotConnectToPostgres{
          host: "db.example.com",
          port: 5432,
          reason: :closed
        })

      assert closed =~ "closed the connection"

      unreachable =
        Error.format(%CannotConnectToPostgres{
          host: "db.example.com",
          port: 5432,
          reason: :unreachable
        })

      assert unreachable =~ "is unreachable"

      nxdomain =
        Error.format(%CannotConnectToPostgres{
          host: "missing.example",
          port: 5432,
          reason: :nxdomain
        })

      assert nxdomain =~ "could not be resolved"

      unknown_nil =
        Error.format(%CannotConnectToPostgres{
          host: "db.example.com",
          port: 5432,
          reason: :unknown,
          detail: nil,
          message: nil
        })

      assert unknown_nil =~ "unexpected connection error"

      unknown_term =
        Error.format(%CannotConnectToPostgres{
          host: "db.example.com",
          port: 5432,
          reason: :unknown,
          detail: {:posix, :econnreset},
          message: nil
        })

      assert unknown_term =~ "{:posix, :econnreset}"
    end
  end

  defp connection_options(overrides \\ []) do
    struct!(
      %ConnectionOptions{
        host: "127.0.0.1",
        port: 1,
        user: "postgres",
        password: "",
        database: "postgres",
        timeout_seconds: 5
      },
      overrides
    )
  end
end
