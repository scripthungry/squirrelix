defmodule SquirrelixInferenceInferrer do
  @behaviour Squirrelix.Inference.Inferrer

  @impl Squirrelix.Inference.Inferrer
  def infer(_query) do
    {:ok, [params: [], returns: [%{name: "id", type: :integer, nullable?: false}]]}
  end
end

defmodule SquirrelixInferenceTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Inference
  alias Squirrelix.Parameter
  alias Squirrelix.Query
  alias Squirrelix.QueryDirectory
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypedQueryDirectory

  test "from_query_directories types queries using an inferrer function" do
    query = query("find_account.sql", "find_account", "select name from accounts where id = $1")

    inferrer = fn ^query ->
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
           ] = Inference.from_query_directories([query_directory([query])], inferrer)
  end

  test "from_query_directories accepts inferrer modules" do
    query = query("find_account.sql", "find_account", "select 1")

    assert [%TypedQueryDirectory{queries: [%TypedQuery{name: "find_account"}], errors: []}] =
             Inference.from_query_directories(
               [query_directory([query])],
               SquirrelixInferenceInferrer
             )
  end

  test "from_query_directories preserves parse and inference errors" do
    query = query("broken.sql", "broken", "select broken")
    parse_error = %Squirrelix.Error.CannotReadFile{file: "missing.sql", reason: :enoent}
    inference_error = %Squirrelix.Error.UnsupportedPostgresType{name: "point"}

    inferrer = fn ^query -> {:error, inference_error} end

    assert [
             %TypedQueryDirectory{
               queries: [],
               errors: [^parse_error, ^inference_error]
             }
           ] =
             Inference.from_query_directories(
               [query_directory([query], [parse_error])],
               inferrer
             )
  end

  test "from_query_directories normalizes postgres inference errors for the failing query" do
    query = query("broken.sql", "broken", "select broken")

    inference_error = %Squirrelix.Error.PostgresInferenceError{
      file: "other.sql",
      starting_line: 99,
      content: "stale content",
      message: "constraint \"wobble\" for table \"squirrel\" does not exist",
      code: :undefined_object,
      position: nil
    }

    inferrer = fn ^query -> {:error, inference_error} end

    assert [
             %TypedQueryDirectory{
               errors: [
                 %Squirrelix.Error.MissingPostgresConstraint{
                   file: "broken.sql",
                   content: "select broken",
                   constraint: "wobble",
                   table: "squirrel"
                 }
               ]
             }
           ] = Inference.from_query_directories([query_directory([query])], inferrer)
  end

  defp query(file, name, content) do
    %Query{file: file, starting_line: 1, name: name, comment: [], content: content}
  end

  defp query_directory(queries, errors \\ []) do
    %QueryDirectory{directory: "lib/accounts/sql", queries: queries, errors: errors}
  end
end
