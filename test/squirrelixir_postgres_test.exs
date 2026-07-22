defmodule SquirrelixirPostgresTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Squirrelixir.CodegenSummary
  alias Squirrelixir.Column
  alias Squirrelixir.Error.MissingPostgresColumn
  alias Squirrelixir.Error.MissingPostgresTable
  alias Squirrelixir.Error.PostgresSyntaxError
  alias Squirrelixir.Error.QueryHasInvalidEnum
  alias Squirrelixir.Error.UnsupportedPostgresType
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

  test "infer infers parameter and return types from a prepared query", %{conn: conn} do
    query = query("select 1::int4 as id, $1::text as name")

    assert {:ok,
            [
              params: [:string],
              returns: [
                %Column{name: "id", type: :integer, nullable?: false},
                %Column{name: "name", type: :string, nullable?: false}
              ]
            ]} = Postgres.infer(conn, query)
  end

  test "infer infers array dimensions", %{conn: conn} do
    query = query("select $1::int4[] as ids")

    assert {:ok,
            [
              params: [{:list, :integer}],
              returns: [%Column{name: "ids", type: {:list, :integer}, nullable?: false}]
            ]} = Postgres.infer(conn, query)
  end

  test "infer infers custom enum types as strings", %{conn: conn} do
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
              ]} = Postgres.infer(conn, query)
    end)
  end

  test "infer infers enums with quoted names and numeric variants as strings", %{conn: conn} do
    Postgrex.query!(conn, "drop type if exists \"1 invalid enum\"", [])
    Postgrex.query!(conn, ~s/create type "1 invalid enum" as enum ('value')/, [])

    query = query(~s/select 'value'::"1 invalid enum" as res/)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "res", type: :string, nullable?: false}
              ]
            ]} = Postgres.infer(conn, query)
  end

  test "infer infers enums with non-identifier variant labels as strings", %{conn: conn} do
    Postgrex.query!(conn, "drop type if exists invalid_variant", [])
    Postgrex.query!(conn, "create type invalid_variant as enum ('1 invalid value')", [])

    query = query("select '1 invalid value'::invalid_variant as res")

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "res", type: :string, nullable?: false}
              ]
            ]} = Postgres.infer(conn, query)
  end

  test "infer rejects enums with no variants", %{conn: conn} do
    Postgrex.query!(conn, "drop type if exists no_variants", [])
    Postgrex.query!(conn, "create type no_variants as enum ()", [])

    query = query("select $1::no_variants as res")

    assert {:error, %QueryHasInvalidEnum{enum_name: "no_variants", reason: :no_variants}} =
             Postgres.infer(conn, query)
  end

  test "infer infers custom domain types from their base type", %{conn: conn} do
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
              ]} = Postgres.infer(conn, query)
    end)
  end

  test "infer infers timestamp with time zone as utc datetime", %{conn: conn} do
    query = query("select now() as occurred_at")

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "occurred_at", type: :utc_datetime, nullable?: false}
              ]
            ]} = Postgres.infer(conn, query)
  end

  test "infer infers common scalar result types", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  test "infer marks not-null table columns as non-nullable", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  test "infer keeps left joined columns nullable", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  test "infer keeps unaliased left joined columns nullable", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  test "infer keeps right joined base columns nullable", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  test "infer keeps full joined columns nullable", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  @tag :cte
  test "infer infers nullability for CTE queries", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  @tag :cte
  test "infer infers nullability for CTE with left join", %{conn: conn} do
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
            ]} = Postgres.infer(conn, query)
  end

  test "infer output can be converted into a typed query", %{conn: conn} do
    query = %Query{
      file: "find_account.sql",
      starting_line: 1,
      name: "find_account",
      comment: [],
      content: "select $1::text as name"
    }

    assert {:ok, metadata} = Postgres.infer(conn, query)

    assert {:ok,
            %Squirrelixir.TypedQuery{
              params: [%Parameter{name: nil, type: :string}],
              returns: [%Column{name: "name", type: :string, nullable?: false}]
            }} = Squirrelixir.TypedQuery.from_query(query, metadata)
  end

  test "infer returns a structured syntax error", %{conn: conn} do
    query = query("select from")

    assert {:error,
            %PostgresSyntaxError{
              file: "query.sql",
              starting_line: 1,
              content: "select from",
              message: "syntax error at end of input",
              position: 12
            }} = Postgres.infer(conn, query)
  end

  test "infer returns a structured missing table error", %{conn: conn} do
    query = query("select * from squirrelixir_missing_table")

    assert {:error,
            %MissingPostgresTable{
              file: "query.sql",
              starting_line: 1,
              content: "select * from squirrelixir_missing_table",
              message: "relation \"squirrelixir_missing_table\" does not exist",
              table: "squirrelixir_missing_table",
              position: 15
            }} = Postgres.infer(conn, query)
  end

  test "infer returns a structured missing column error", %{conn: conn} do
    query = query("select missing_column from pg_type")

    assert {:error,
            %MissingPostgresColumn{
              file: "query.sql",
              starting_line: 1,
              content: "select missing_column from pg_type",
              message: "column \"missing_column\" does not exist",
              column: "missing_column",
              position: 8
            }} = Postgres.infer(conn, query)
  end

  test "infer infers nullability for parameterized left joins using foreign keys", %{
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
            ]} = Postgres.infer(conn, query)
  end

  # https://github.com/giacomocavalieri/squirrel/issues/75
  # Mirrors Gleam recursive_common_table_query_with_semi_join_test: SQL uses a left
  # join plus an IN subquery that Postgres plans as a semi join.
  @tag :cte
  test "infer infers nullability for recursive common table query with semi join", %{
    conn: conn
  } do
    Postgrex.query!(conn, "drop table if exists categories_issue75", [])
    Postgrex.query!(conn, "drop table if exists items_issue75", [])
    Postgrex.query!(conn, "drop table if exists items_categories_issue75", [])

    Postgrex.query!(
      conn,
      """
      create temporary table categories_issue75 (
        id uuid primary key,
        name varchar(70) not null,
        parent_id uuid not null
      )
      """,
      []
    )

    Postgrex.query!(
      conn,
      "create temporary table items_issue75 (id uuid primary key, name varchar(70) not null)",
      []
    )

    Postgrex.query!(
      conn,
      """
      create temporary table items_categories_issue75 (
        item_id uuid not null,
        category_id uuid not null,
        primary key (item_id, category_id)
      )
      """,
      []
    )

    query =
      query("""
      with recursive subcategories as (
        select id
        from categories_issue75
        where id = $1

        union all

        select c.id
        from categories_issue75 c
        join subcategories sc on c.parent_id = sc.id
      )
      select i.id, i.name
      from items_issue75 i
      left join items_categories_issue75 ic on ic.item_id = i.id
      where ic.category_id in (select id from subcategories);
      """)

    assert {:ok,
            [
              params: [:uuid],
              returns: [
                %Column{name: "id", type: :uuid, nullable?: false},
                %Column{name: "name", type: :string, nullable?: false}
              ]
            ]} = Postgres.infer(conn, query)
  end

  test "infer accepts queries starting with a semicolon", %{conn: conn} do
    query = query(";select 1::int4 as result")

    assert {:ok,
            [
              params: [],
              returns: [%Column{name: "result", type: :integer, nullable?: false}]
            ]} = Postgres.infer(conn, query)
  end

  # https://github.com/giacomocavalieri/squirrel/issues/41
  test "infer keeps left joined not-null columns nullable", %{conn: conn} do
    Postgrex.query!(conn, "drop table if exists profile_issue41 cascade", [])
    Postgrex.query!(conn, "drop table if exists users_issue41 cascade", [])

    Postgrex.query!(
      conn,
      "create temporary table users_issue41 (user_id bigserial primary key)",
      []
    )

    Postgrex.query!(
      conn,
      """
      create temporary table profile_issue41 (
        profile_id bigserial primary key,
        user_id bigint not null,
        roles text not null
      )
      """,
      []
    )

    query =
      query("""
      select
        users_issue41.user_id,
        profile_issue41.roles
      from
        users_issue41
        left join profile_issue41
          on profile_issue41.user_id = users_issue41.user_id
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "user_id", type: :integer, nullable?: false},
                %Column{name: "roles", type: :string, nullable?: true}
              ]
            ]} = Postgres.infer(conn, query)
  end

  test "infer keeps aliased using join columns optional for outer joins", %{conn: conn} do
    Postgrex.query!(conn, "drop table if exists squirrelixir_using_left", [])
    Postgrex.query!(conn, "drop table if exists squirrelixir_using_right", [])

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_using_left (name text primary key, acorns int)",
      []
    )

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_using_right (name text primary key, acorns int)",
      []
    )

    left_query =
      query("""
      select
        s1.name as not_optional,
        s2.name as optional
      from
        squirrelixir_using_left s1
        left join squirrelixir_using_right s2 using(name)
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "not_optional", type: :string, nullable?: false},
                %Column{name: "optional", type: :string, nullable?: true}
              ]
            ]} = Postgres.infer(conn, left_query)

    right_query =
      query("""
      select
        s1.name as optional,
        s2.name as not_optional
      from
        squirrelixir_using_left s1
        right join squirrelixir_using_right s2 using(name)
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "optional", type: :string, nullable?: true},
                %Column{name: "not_optional", type: :string, nullable?: false}
              ]
            ]} = Postgres.infer(conn, right_query)

    full_query =
      query("""
      select
        s1.name as optional1,
        s2.name as optional2
      from
        squirrelixir_using_left s1
        full join squirrelixir_using_right s2 using(name)
      """)

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "optional1", type: :string, nullable?: true},
                %Column{name: "optional2", type: :string, nullable?: true}
              ]
            ]} = Postgres.infer(conn, full_query)
  end

  test "infer marks nullable table columns as optional", %{conn: conn} do
    Postgrex.query!(conn, "drop table if exists squirrelixir_optional_acorns", [])

    Postgrex.query!(
      conn,
      "create temporary table squirrelixir_optional_acorns (name text primary key, acorns int)",
      []
    )

    query = query("select acorns from squirrelixir_optional_acorns")

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "acorns", type: :integer, nullable?: true}
              ]
            ]} = Postgres.infer(conn, query)
  end

  test "infer accepts do blocks", %{conn: conn} do
    query =
      query("""
      do $$ begin
        select 1::int4 as value;
      end $$;
      """)

    assert {:ok, [params: [], returns: []]} = Postgres.infer(conn, query)
  end

  test "inferrer can generate modules from a live Postgres connection", %{conn: conn} do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    File.write!(Path.join(sql_directory, "find_account.sql"), "select $1::text as name")

    assert Squirrelixir.generate(root, Postgres.inferrer(conn), version: "v-test") ==
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

  describe "postgres string types and unsupported built-ins" do
    setup %{conn: conn} do
      Postgrex.query!(conn, "create extension if not exists citext", [])
      :ok
    end

    test "infer infers char-like Postgres types as string", %{conn: conn} do
      query =
        query("""
        select
          'a'::char as char_value,
          'label'::bpchar as bpchar_value,
          'wibble'::citext as citext_value,
          'pg_catalog'::name as name_value
        """)

      assert {:ok,
              [
                params: [],
                returns: [
                  %Column{name: "char_value", type: :string, nullable?: false},
                  %Column{name: "bpchar_value", type: :string, nullable?: false},
                  %Column{name: "citext_value", type: :string, nullable?: false},
                  %Column{name: "name_value", type: :string, nullable?: false}
                ]
              ]} = Postgres.infer(conn, query)
    end

    test "infer infers char-like parameters as string", %{conn: conn} do
      query =
        query("""
        select
          $1::char as char_value,
          $2::citext as citext_value,
          $3::name as name_value
        """)

      assert {:ok,
              [
                params: [:string, :string, :string],
                returns: [
                  %Column{name: "char_value", type: :string, nullable?: false},
                  %Column{name: "citext_value", type: :string, nullable?: false},
                  %Column{name: "name_value", type: :string, nullable?: false}
                ]
              ]} = Postgres.infer(conn, query)
    end

    test "infer infers name arrays as string lists", %{conn: conn} do
      query = query("select $1::name[] as names, '{}'::name[] as empty_names")

      assert {:ok,
              [
                params: [{:list, :string}],
                returns: [
                  %Column{name: "names", type: {:list, :string}, nullable?: false},
                  %Column{name: "empty_names", type: {:list, :string}, nullable?: false}
                ]
              ]} = Postgres.infer(conn, query)
    end

    test "infer infers timestamp with time zone as utc datetime", %{conn: conn} do
      query = query("select $1::timestamptz as occurred_at, now() as current_at")

      assert {:ok,
              [
                params: [:utc_datetime],
                returns: [
                  %Column{name: "occurred_at", type: :utc_datetime, nullable?: false},
                  %Column{name: "current_at", type: :utc_datetime, nullable?: false}
                ]
              ]} = Postgres.infer(conn, query)
    end

    test "infer rejects point and composite Postgres types", %{conn: conn} do
      Postgrex.query!(conn, "drop type if exists squirrelixir_point cascade", [])

      Postgrex.query!(
        conn,
        "create type squirrelixir_point as (x double precision, y double precision)",
        []
      )

      assert {:error, %UnsupportedPostgresType{name: "point", hint: nil}} =
               Postgres.infer(conn, query("select point(1, 2) as location"))

      assert {:error, %UnsupportedPostgresType{name: "point", hint: nil}} =
               Postgres.infer(conn, query("select $1::point as location"))

      assert {:error, %UnsupportedPostgresType{name: "squirrelixir_point", hint: nil}} =
               Postgres.infer(
                 conn,
                 query("select '(1,2)'::squirrelixir_point as location")
               )
    end
  end
end
