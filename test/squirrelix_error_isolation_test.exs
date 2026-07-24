defmodule SquirrelixErrorIsolationTest do
  use ExUnit.Case, async: false

  alias Squirrelix.Error
  alias Squirrelix.Error.MissingPostgresColumn
  alias Squirrelix.Error.MissingPostgresConstraint
  alias Squirrelix.Error.MissingPostgresTable
  alias Squirrelix.Error.PostgresSyntaxError
  alias Squirrelix.Inference
  alias Squirrelix.Postgres
  alias Squirrelix.Query
  alias Squirrelix.QueryDirectory
  alias Squirrelix.TypedQueryDirectory

  setup_all do
    case Postgrex.start_link(Squirrelix.TestSupport.postgres_opts()) do
      {:ok, conn} ->
        Postgrex.query!(
          conn,
          "create temporary table if not exists squirrel (name text primary key, acorns int)",
          []
        )

        on_exit(fn -> GenServer.stop(conn) end)
        {:ok, conn: conn}

      {:error, reason} ->
        flunk("local Postgres is required for this test: #{inspect(reason)}")
    end
  end

  describe "query inference errors" do
    test "query_with_syntax_error returns a structured syntax error", %{conn: conn} do
      query =
        query("query.sql", "query", """
        select
          name wibble wobble
        from
          squirrel
        """)

      assert {:error,
              %PostgresSyntaxError{
                file: "query.sql",
                message: "syntax error at or near \"wobble\"",
                position: 22
              }} = Postgres.infer(conn, query)

      formatted = Error.format(Postgres.infer(conn, query) |> elem(1))
      assert formatted =~ "Invalid query [42601]"
      assert formatted =~ "query.sql"
      assert formatted =~ "syntax error at or near \"wobble\""
      assert formatted =~ "wobble"
      assert formatted =~ "╰─ syntax error at or near \"wobble\""
    end

    test "query_with_table_that_doesnt_exist returns a structured missing table error", %{
      conn: conn
    } do
      query =
        query("query.sql", "query", """
        select
          name
        from
          i_do_not_exist
        """)

      assert {:error,
              %MissingPostgresTable{
                file: "query.sql",
                message: "relation \"i_do_not_exist\" does not exist",
                table: "i_do_not_exist",
                position: 22
              }} = Postgres.infer(conn, query)

      formatted = Error.format(Postgres.infer(conn, query) |> elem(1))
      assert formatted =~ "Invalid query [42P01]"
      assert formatted =~ "i_do_not_exist"
    end

    test "query_with_column_that_doesnt_exist returns a structured missing column error", %{
      conn: conn
    } do
      query =
        query("query.sql", "query", """
        select
          i_do_not_exist
        from
          squirrel
        """)

      assert {:error,
              %MissingPostgresColumn{
                file: "query.sql",
                message: "column \"i_do_not_exist\" does not exist",
                column: "i_do_not_exist",
                position: 10
              }} = Postgres.infer(conn, query)

      formatted = Error.format(Postgres.infer(conn, query) |> elem(1))
      assert formatted =~ "Invalid query [42703]"
      assert formatted =~ "i_do_not_exist"
    end

    test "non_existing_constraint_error_message returns a structured constraint error", %{
      conn: conn
    } do
      query =
        query(
          "query.sql",
          "query",
          """
          insert into squirrel values ($1, $2)
          on conflict on constraint wobble do nothing;
          """
        )

      assert {:error, error} = Postgres.infer(conn, query)

      assert %MissingPostgresConstraint{
               file: "query.sql",
               message: "constraint \"wobble\" for table \"squirrel\" does not exist",
               constraint: "wobble",
               table: "squirrel"
             } = Error.normalize(error)

      formatted = Error.format(error)
      assert formatted =~ "Invalid query [42704]"
      assert formatted =~ "constraint \"wobble\" for table \"squirrel\" does not exist"
      assert formatted =~ "query.sql"
      assert formatted =~ "on conflict on constraint wobble do nothing"
    end
  end

  describe "a query failing does not change the other query's error" do
    test "missing tables are reported independently for sibling queries", %{conn: conn} do
      directory =
        query_directory([
          {"wibble.sql", "wibble", "select wibble from wibble"},
          {"wobble.sql", "wobble", "select wobble from wobble"}
        ])

      assert [%TypedQueryDirectory{queries: [], errors: errors}] =
               Inference.from_query_directories([directory], Postgres.inferrer(conn))

      assert [
               %MissingPostgresTable{
                 file: "wibble.sql",
                 content: "select wibble from wibble",
                 table: "wibble"
               },
               %MissingPostgresTable{
                 file: "wobble.sql",
                 content: "select wobble from wobble",
                 table: "wobble"
               }
             ] = normalize_errors(errors)

      formatted = Error.format_all(errors)
      assert formatted =~ "wibble.sql"
      assert formatted =~ "select wibble from wibble"
      assert formatted =~ "wobble.sql"
      assert formatted =~ "select wobble from wobble"
    end

    test "a syntax error in one query does not change the other query's error", %{conn: conn} do
      directory =
        query_directory([
          {"wibble.sql", "wibble", "error! select 1 as res"},
          {"wobble.sql", "wobble", "select wobble from wobble"}
        ])

      assert [%TypedQueryDirectory{queries: [], errors: errors}] =
               Inference.from_query_directories([directory], Postgres.inferrer(conn))

      assert [
               %PostgresSyntaxError{
                 file: "wibble.sql",
                 content: "error! select 1 as res",
                 message: "syntax error at or near \"error\""
               },
               %MissingPostgresTable{
                 file: "wobble.sql",
                 content: "select wobble from wobble",
                 table: "wobble"
               }
             ] = normalize_errors(errors)
    end
  end

  describe "query directory error isolation" do
    test "from_files keeps parse errors aligned with their files" do
      dir = Squirrelix.TestSupport.tmp_dir!("squirr_elix-error-isolation")

      valid = write_sql(dir, "valid.sql", "select 1")
      invalid = write_sql(dir, "01 invalid.sql", "select 1")

      assert %QueryDirectory{
               queries: [%Query{file: ^valid, content: "select 1"}],
               errors: [%Squirrelix.Error.QueryFileHasInvalidName{file: ^invalid}]
             } = QueryDirectory.from_files(dir, [invalid, valid])
    end
  end

  defp query(file, name, content) do
    %Query{file: file, starting_line: 1, name: name, comment: [], content: content}
  end

  defp query_directory(entries) do
    queries =
      Enum.map(entries, fn {file, name, content} ->
        query(file, name, content)
      end)

    %QueryDirectory{directory: "test/sql", queries: queries, errors: []}
  end

  defp write_sql(dir, file_name, content) do
    path = Path.join(dir, file_name)
    File.write!(path, content)
    path
  end

  defp normalize_errors(errors), do: Enum.map(errors, &Error.normalize/1)
end
