defmodule SquirrelixirInferenceDescriber do
  @behaviour Squirrelixir.Inference.Describer

  @impl Squirrelixir.Inference.Describer
  def describe(_query) do
    {:ok, [params: [], returns: [%{name: "id", type: :integer, nullable?: false}]]}
  end
end

defmodule SquirrelixirInferenceTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Inference
  alias Squirrelixir.Parameter
  alias Squirrelixir.Query
  alias Squirrelixir.QueryDirectory
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

  test "from_query_directories types queries using a describer function" do
    query = query("find_account.sql", "find_account", "select name from accounts where id = $1")

    describer = fn ^query ->
      {:ok,
       [
         params: [{:postgres, "int4"}],
         returns: [%{name: "name", type: {:postgres, "text"}, nullable?: false}]
       ]}
    end

    assert [
             %TypedQueryDirectory{
               directory: "lib/accounts/sql",
               queries: [
                 %TypedQuery{
                   name: "find_account",
                   params: [%Parameter{name: "id", type: :integer}]
                 }
               ],
               errors: []
             }
           ] = Inference.from_query_directories([query_directory([query])], describer)
  end

  test "from_query_directories accepts describer modules" do
    query = query("find_account.sql", "find_account", "select 1")

    assert [%TypedQueryDirectory{queries: [%TypedQuery{name: "find_account"}], errors: []}] =
             Inference.from_query_directories(
               [query_directory([query])],
               SquirrelixirInferenceDescriber
             )
  end

  test "from_query_directories preserves parse and describe errors" do
    query = query("broken.sql", "broken", "select broken")
    parse_error = %Squirrelixir.Error.CannotReadFile{file: "missing.sql", reason: :enoent}
    describe_error = %Squirrelixir.Error.UnsupportedPostgresType{name: "point"}

    describer = fn ^query -> {:error, describe_error} end

    assert [
             %TypedQueryDirectory{
               queries: [],
               errors: [^parse_error, ^describe_error]
             }
           ] =
             Inference.from_query_directories(
               [query_directory([query], [parse_error])],
               describer
             )
  end

  test "from_query_directories normalizes postgres inference errors for the failing query" do
    query = query("broken.sql", "broken", "select broken")

    inference_error = %Squirrelixir.Error.PostgresInferenceError{
      file: "other.sql",
      starting_line: 99,
      content: "stale content",
      message: "constraint \"wobble\" for table \"squirrel\" does not exist",
      code: :undefined_object,
      position: nil
    }

    describer = fn ^query -> {:error, inference_error} end

    assert [
             %TypedQueryDirectory{
               errors: [
                 %Squirrelixir.Error.MissingPostgresConstraint{
                   file: "broken.sql",
                   content: "select broken",
                   constraint: "wobble",
                   table: "squirrel"
                 }
               ]
             }
           ] = Inference.from_query_directories([query_directory([query])], describer)
  end

  defp query(file, name, content) do
    %Query{file: file, starting_line: 1, name: name, comment: [], content: content}
  end

  defp query_directory(queries, errors \\ []) do
    %QueryDirectory{directory: "lib/accounts/sql", queries: queries, errors: errors}
  end
end
