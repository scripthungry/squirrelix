defmodule SquirrElixInferenceInferrer do
  @behaviour SquirrElix.Inference.Inferrer

  @impl SquirrElix.Inference.Inferrer
  def infer(_query) do
    {:ok, [params: [], returns: [%{name: "id", type: :integer, nullable?: false}]]}
  end
end

defmodule SquirrElixInferenceTest do
  use ExUnit.Case, async: true

  alias SquirrElix.Inference
  alias SquirrElix.Parameter
  alias SquirrElix.Query
  alias SquirrElix.QueryDirectory
  alias SquirrElix.TypedQuery
  alias SquirrElix.TypedQueryDirectory

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
               SquirrElixInferenceInferrer
             )
  end

  test "from_query_directories preserves parse and inference errors" do
    query = query("broken.sql", "broken", "select broken")
    parse_error = %SquirrElix.Error.CannotReadFile{file: "missing.sql", reason: :enoent}
    inference_error = %SquirrElix.Error.UnsupportedPostgresType{name: "point"}

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

    inference_error = %SquirrElix.Error.PostgresInferenceError{
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
                 %SquirrElix.Error.MissingPostgresConstraint{
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
