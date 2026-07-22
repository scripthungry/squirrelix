defmodule SquirrelixirPostgresTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Squirrelixir.CodegenSummary
  alias Squirrelixir.Column
  alias Squirrelixir.Error.MissingPostgresColumn
  alias Squirrelixir.Error.MissingPostgresTable
  alias Squirrelixir.Error.PostgresSyntaxError
  alias Squirrelixir.Parameter
  alias Squirrelixir.Postgres
  alias Squirrelixir.Query

  setup_all do
    opts = [
      hostname: "localhost",
      username: System.get_env("USER"),
      database: "postgres",
      log: false
    ]

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        on_exit(fn -> GenServer.stop(conn) end)
        {:ok, conn: conn}

      {:error, reason} ->
        flunk("local Postgres is required for this test: #{inspect(reason)}")
    end
  end

  test "describe infers parameter and return types from a prepared query", %{conn: conn} do
    query = query("select 1::int4 as id, $1::text as name")

    assert {:ok,
            [
              params: [:string],
              returns: [
                %Column{name: "id", type: :integer, nullable?: false},
                %Column{name: "name", type: :string, nullable?: false}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe infers array dimensions", %{conn: conn} do
    query = query("select $1::int4[] as ids")

    assert {:ok,
            [
              params: [{:list, :integer}],
              returns: [%Column{name: "ids", type: {:list, :integer}, nullable?: false}]
            ]} = Postgres.describe(conn, query)
  end

  test "describe infers custom enum types as strings", %{conn: conn} do
    Postgrex.query!(conn, "drop type if exists squirrelixir_mood", [])
    Postgrex.query!(conn, "create type squirrelixir_mood as enum ('happy', 'sleepy')", [])

    query = query("select $1::squirrelixir_mood as mood, $2::squirrelixir_mood[] as moods")

    capture_log(fn ->
      assert {:ok,
              [
                params: [:string, {:list, :string}],
                returns: [
                  %Column{name: "mood", type: :string, nullable?: false},
                  %Column{name: "moods", type: {:list, :string}, nullable?: false}
                ]
              ]} = Postgres.describe(conn, query)
    end)
  end

  test "describe infers custom domain types from their base type", %{conn: conn} do
    Postgrex.query!(conn, "drop domain if exists squirrelixir_email cascade", [])
    Postgrex.query!(conn, "create domain squirrelixir_email as text", [])

    query = query("select $1::squirrelixir_email as email, $2::squirrelixir_email[] as emails")

    capture_log(fn ->
      assert {:ok,
              [
                params: [:string, {:list, :string}],
                returns: [
                  %Column{name: "email", type: :string, nullable?: false},
                  %Column{name: "emails", type: {:list, :string}, nullable?: false}
                ]
              ]} = Postgres.describe(conn, query)
    end)
  end

  test "describe infers timestamp with time zone as utc datetime", %{conn: conn} do
    query = query("select now() as occurred_at")

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "occurred_at", type: :utc_datetime, nullable?: false}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe infers common scalar result types", %{conn: conn} do
    query =
      query("""
      select
        true::bool as active,
        1.5::float8 as score,
        1.5::numeric as amount,
        '{"a": 1}'::jsonb as payload,
        '00000000-0000-0000-0000-000000000001'::uuid as public_id,
        'abc'::bytea as bytes,
        '2024-01-02'::date as happened_on,
        '03:04:05'::time as happened_at,
        '2024-01-02 03:04:05'::timestamp as recorded_at
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "active", type: :boolean},
                %Column{name: "score", type: :float},
                %Column{name: "amount", type: :decimal},
                %Column{name: "payload", type: :map},
                %Column{name: "public_id", type: :uuid},
                %Column{name: "bytes", type: :binary},
                %Column{name: "happened_on", type: :date},
                %Column{name: "happened_at", type: :time},
                %Column{name: "recorded_at", type: :naive_datetime}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe marks not-null table columns as non-nullable", %{conn: conn} do
    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_people (id integer not null, nickname text)",
      []
    )

    query = query("select id, nickname from squirrelixir_people")

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "id", type: :integer, nullable?: false},
                %Column{name: "nickname", type: :string, nullable?: true}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe keeps left joined columns nullable", %{conn: conn} do
    create_join_tables(conn)

    query =
      query("""
      select teams.name as team_name, members.name as member_name
      from squirrelixir_teams teams
      left join squirrelixir_members members on members.team_id = teams.id
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "team_name", type: :string, nullable?: false},
                %Column{name: "member_name", type: :string, nullable?: true}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe keeps unaliased left joined columns nullable", %{conn: conn} do
    create_join_tables(conn)

    query =
      query("""
      select squirrelixir_teams.name as team_name, squirrelixir_members.name as member_name
      from squirrelixir_teams
      left join squirrelixir_members using(name)
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "team_name", type: :string, nullable?: false},
                %Column{name: "member_name", type: :string, nullable?: true}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe keeps right joined base columns nullable", %{conn: conn} do
    create_join_tables(conn)

    query =
      query("""
      select teams.name as team_name, members.name as member_name
      from squirrelixir_teams teams
      right join squirrelixir_members members on members.team_id = teams.id
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "team_name", type: :string, nullable?: true},
                %Column{name: "member_name", type: :string, nullable?: false}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe keeps full joined columns nullable", %{conn: conn} do
    create_join_tables(conn)

    query =
      query("""
      select teams.name as team_name, members.name as member_name
      from squirrelixir_teams teams
      full join squirrelixir_members members on members.team_id = teams.id
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "team_name", type: :string, nullable?: true},
                %Column{name: "member_name", type: :string, nullable?: true}
              ]
            ]} = Postgres.describe(conn, query)
  end

  @tag :cte
  test "describe infers nullability for CTE queries", %{conn: conn} do
    Postgrex.query!(conn, "drop table if exists squirrelixir_cte_users", [])

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_cte_users (id integer not null, name text not null)",
      []
    )

    query =
      query("""
      with cte as (
        select id, name from squirrelixir_cte_users
      )
      select id, name from cte
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "id", type: :integer, nullable?: false},
                %Column{name: "name", type: :string, nullable?: false}
              ]
            ]} = Postgres.describe(conn, query)
  end

  @tag :cte
  test "describe infers nullability for CTE with left join", %{conn: conn} do
    Postgrex.query!(conn, "drop table if exists squirrelixir_cte_users", [])
    Postgrex.query!(conn, "drop table if exists squirrelixir_cte_members", [])

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_cte_users (id integer not null, name text not null)",
      []
    )

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_cte_members (team_id integer, name text)",
      []
    )

    query =
      query("""
      with cte as (
        select id, name from squirrelixir_cte_users
      )
      select c.id, m.name
      from cte c
      left join squirrelixir_cte_members m on m.team_id = c.id
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "id", type: :integer, nullable?: false},
                %Column{name: "name", type: :string, nullable?: true}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe output can be converted into a typed query", %{conn: conn} do
    query = %Query{
      file: "find_account.sql",
      starting_line: 1,
      name: "find_account",
      comment: [],
      content: "select $1::text as name"
    }

    assert {:ok, metadata} = Postgres.describe(conn, query)

    assert {:ok,
            %Squirrelixir.TypedQuery{
              params: [%Parameter{name: nil, type: :string}],
              returns: [%Column{name: "name", type: :string, nullable?: false}]
            }} = Squirrelixir.TypedQuery.from_query(query, metadata)
  end

  test "describe returns a structured syntax error", %{conn: conn} do
    query = query("select from")

    assert {:error,
            %PostgresSyntaxError{
              file: "query.sql",
              starting_line: 1,
              content: "select from",
              message: "syntax error at end of input",
              position: 12
            }} = Postgres.describe(conn, query)
  end

  test "describe returns a structured missing table error", %{conn: conn} do
    query = query("select * from squirrelixir_missing_table")

    assert {:error,
            %MissingPostgresTable{
              file: "query.sql",
              starting_line: 1,
              content: "select * from squirrelixir_missing_table",
              message: "relation \"squirrelixir_missing_table\" does not exist",
              table: "squirrelixir_missing_table",
              position: 15
            }} = Postgres.describe(conn, query)
  end

  test "describe returns a structured missing column error", %{conn: conn} do
    query = query("select missing_column from pg_type")

    assert {:error,
            %MissingPostgresColumn{
              file: "query.sql",
              starting_line: 1,
              content: "select missing_column from pg_type",
              message: "column \"missing_column\" does not exist",
              column: "missing_column",
              position: 8
            }} = Postgres.describe(conn, query)
  end

  test "describe infers nullability for parameterized left joins using foreign keys", %{
    conn: conn
  } do
    Postgrex.query!(conn, "drop table if exists squirrelixir_items_fk", [])
    Postgrex.query!(conn, "drop table if exists squirrelixir_categories_fk", [])

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_categories_fk (category_id integer not null, name text not null)",
      []
    )

    Postgrex.query!(
      conn,
      """
      create temporary table squirrelixir_items_fk (
        item_id integer not null,
        site_id integer not null,
        category_id integer
      )
      """,
      []
    )

    query =
      query("""
      select
        squirrelixir_items_fk.item_id,
        squirrelixir_categories_fk.name
      from squirrelixir_items_fk
      left join squirrelixir_categories_fk using(category_id)
      where squirrelixir_items_fk.site_id = $1
      """)

    assert {:ok,
            [
              params: [:integer],
              returns: [
                %Column{name: "item_id", type: :integer, nullable?: false},
                %Column{name: "name", type: :string, nullable?: true}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe accepts queries starting with a semicolon", %{conn: conn} do
    query = query(";select 1::int4 as result")

    assert {:ok,
            [
              params: [],
              returns: [%Column{name: "result", type: :integer, nullable?: true}]
            ]} = Postgres.describe(conn, query)
  end

  test "describe accepts do blocks", %{conn: conn} do
    query =
      query("""
      do $$ begin
        select 1::int4 as value;
      end $$;
      """)

    assert {:ok, [params: [], returns: []]} = Postgres.describe(conn, query)
  end

  test "describer can generate modules from a live Postgres connection", %{conn: conn} do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    File.write!(Path.join(sql_directory, "find_account.sql"), "select $1::text as name")

    assert Squirrelixir.generate(root, Postgres.describer(conn), version: "v-test") ==
             %CodegenSummary{generated_count: 1, errors: [], status: :ok}

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "required(:name) => String.t()"
  end

  defp query(content) do
    %Query{file: "query.sql", starting_line: 1, name: "query", comment: [], content: content}
  end

  defp create_join_tables(conn) do
    Postgrex.query!(conn, "drop table if exists squirrelixir_members", [])
    Postgrex.query!(conn, "drop table if exists squirrelixir_teams", [])

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_teams (id integer not null, name text not null)",
      []
    )

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_members (team_id integer not null, name text not null)",
      []
    )
  end

  defp tmp_project(app) do
    path = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-postgres")

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
end
