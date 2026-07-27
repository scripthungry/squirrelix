defmodule SquirrelixIntegrationTest do
  @moduledoc """
  End-to-end integration tests proving Squirrelix is a complete Elixir Squirrel.

  ## Elixir workflow vs Gleam Squirrel

  Both tools share the same SQL-on-disk conventions: one statement per `.sql` file
  under a `sql/` directory, file names become function names, and leading SQL
  comments become documentation. Discovery walks conventional source roots.

  Where they diverge is the generated surface and query-source wiring:

    * **Gleam Squirrel** emits Gleam modules with custom ADTs, `Result` types, and
      Gleam-specific decoders. Metadata often lives in a Gleam config module.
    * **Squirrelix** emits Elixir modules with `@spec` annotations, stdlib types
      (`String.t()`, `integer()`, `map/0` row shapes), and Postgrex at runtime.
      Query sources are either a metadata map (like `squirr_elix.exs`) or a
      Postgres inferrer callback — the same split as `mix squirrelix.gen`
      with or without `--infer`.

  These tests exercise the full Elixir path: temp Mix project → `Squirrelix.generate/3`
  → sibling `sql.ex` on disk → `Squirrelix.TestSupport.compile_string/1` → invoke generated functions.
  Live Postgres coverage is optional (`@tag :postgres`) and skips when no local DB
  is available; the default integration tests use static metadata or a stub inferrer
  plus a Postgrex mock so CI does not require a database.
  """

  use ExUnit.Case, async: false

  alias Squirrelix.CodegenCheckSummary
  alias Squirrelix.CodegenSummary
  alias Squirrelix.Postgres

  @tag :integration
  test "generate → compile → invoke with static metadata" do
    root = Squirrelix.TestSupport.tmp_mix_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts where id = $1")

    metadata = %{
      query_file => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert Squirrelix.generate(root, metadata,
             version: "v-integration",
             postgrex: IntegrationPostgrexMock
           ) == %CodegenSummary{
             generated_count: 1,
             errors: [],
             status: :ok
           }

    output_path = Path.join(root, "lib/accounts/sql.ex")
    code = File.read!(output_path)

    assert code =~ "defmodule AcornCounter.Accounts.SQL do"
    assert code =~ "def find_account("
    assert code =~ "required(:name) => String.t()"

    assert Code.ensure_loaded?(Postgrex)

    assert [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)
    assert function_exported?(module, :find_account, 2)

    assert module.find_account({IntegrationPostgrexMock, self()}, 42) == [
             %{name: "Ada"}
           ]

    assert_received {:query!, "select name from accounts where id = $1", [42]}

    assert Squirrelix.check(root, metadata,
             version: "v-integration",
             postgrex: IntegrationPostgrexMock
           ) == %CodegenCheckSummary{
             checked_count: 1,
             errors: [],
             status: :ok
           }
  end

  @tag :integration
  test "generate → compile → invoke with a query inferrer" do
    root = Squirrelix.TestSupport.tmp_mix_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    File.write!(
      Path.join(sql_directory, "find_account.sql"),
      "select name from accounts where id = $1"
    )

    inferrer = fn _query ->
      {:ok,
       [
         params: [{:postgres, "int4"}],
         returns: [%{name: "name", type: {:postgres, "text"}, nullable?: false}]
       ]}
    end

    assert Squirrelix.generate(root, inferrer,
             version: "v-integration",
             postgrex: IntegrationPostgrexMock
           ) == %CodegenSummary{
             generated_count: 1,
             errors: [],
             status: :ok
           }

    code = File.read!(Path.join(root, "lib/accounts/sql.ex"))
    assert [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.find_account({IntegrationPostgrexMock, self()}, 7) == [
             %{name: "Ada"}
           ]

    assert_received {:query!, "select name from accounts where id = $1", [7]}
  end

  @tag :postgres
  test "generate with Postgres.inferrer → compile → invoke on live connection", %{conn: conn} do
    root = Squirrelix.TestSupport.tmp_mix_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    File.write!(
      Path.join(sql_directory, "scalar.sql"),
      "select $1::int4 as value"
    )

    assert Squirrelix.generate(root, Postgres.inferrer(conn), version: "v-integration") ==
             %CodegenSummary{generated_count: 1, errors: [], status: :ok}

    code = File.read!(Path.join(root, "lib/accounts/sql.ex"))
    assert code =~ "required(:value) => integer()"

    assert [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.scalar(conn, 42) == [%{value: 42}]
  end

  setup tags do
    if tags[:postgres] do
      case Postgrex.start_link(Squirrelix.TestSupport.postgres_opts()) do
        {:ok, conn} ->
          on_exit(fn ->
            try do
              GenServer.stop(conn)
            catch
              :exit, _ -> :ok
            end
          end)

          {:ok, conn: conn}

        {:error, reason} ->
          {:ok, skip: "local Postgres unavailable: #{inspect(reason)}"}
      end
    else
      :ok
    end
  end
end

defmodule IntegrationPostgrexMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["name"], rows: [["Ada"]]}
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(%Postgrex.Result{columns: ["name"], rows: [["Ada"]]})
  end
end
