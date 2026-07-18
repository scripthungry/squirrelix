defmodule SquirrelixirPostgresTest do
  use ExUnit.Case, async: false

  alias Squirrelixir.CodegenSummary
  alias Squirrelixir.Column
  alias Squirrelixir.Parameter
  alias Squirrelixir.Postgres
  alias Squirrelixir.Query

  setup_all do
    opts = [hostname: "localhost", username: System.get_env("USER"), database: "postgres"]

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
                %Column{name: "id", type: :integer, nullable?: true},
                %Column{name: "name", type: :string, nullable?: true}
              ]
            ]} = Postgres.describe(conn, query)
  end

  test "describe infers array dimensions", %{conn: conn} do
    query = query("select $1::int4[] as ids")

    assert {:ok,
            [
              params: [{:list, :integer}],
              returns: [%Column{name: "ids", type: {:list, :integer}, nullable?: true}]
            ]} = Postgres.describe(conn, query)
  end

  test "describe infers timestamp with time zone as utc datetime", %{conn: conn} do
    query = query("select now() as occurred_at")

    assert {:ok,
            [
              params: [],
              returns: [
                %Column{name: "occurred_at", type: :utc_datetime, nullable?: true}
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
              returns: [%Column{name: "name", type: :string, nullable?: true}]
            }} = Squirrelixir.TypedQuery.from_query(query, metadata)
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
