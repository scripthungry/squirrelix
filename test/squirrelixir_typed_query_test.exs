defmodule SquirrelixirTypedQueryTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Column
  alias Squirrelixir.Error.DuplicateReturnColumns
  alias Squirrelixir.Parameter
  alias Squirrelixir.Query
  alias Squirrelixir.QueryDirectory
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

  test "from_query attaches parameter names inferred from SQL equality comparisons" do
    query = %Query{
      file: "find_user.sql",
      starting_line: 1,
      name: "find_user",
      comment: ["Finds a user"],
      content: "select name from users where id = $1 and $2 = email"
    }

    assert {:ok,
            %TypedQuery{
              file: "find_user.sql",
              starting_line: 1,
              name: "find_user",
              comment: ["Finds a user"],
              content: "select name from users where id = $1 and $2 = email",
              params: [
                %Parameter{index: 1, name: "id", type: :integer},
                %Parameter{index: 2, name: "email", type: :string},
                %Parameter{index: 3, name: nil, type: :boolean}
              ],
              returns: [%Column{name: "name", type: :string, nullable?: false}]
            }} =
             TypedQuery.from_query(query,
               params: [:integer, :string, :boolean],
               returns: [%{name: "name", type: :string, nullable?: false}]
             )
  end

  test "from_query rejects duplicate return column names" do
    query = %Query{
      file: "duplicate.sql",
      starting_line: 1,
      name: "duplicate",
      comment: [],
      content: "select 1 as duplicate, 2 as duplicate"
    }

    assert {:error,
            %DuplicateReturnColumns{
              file: "duplicate.sql",
              starting_line: 1,
              content: "select 1 as duplicate, 2 as duplicate",
              names: ["duplicate"]
            }} =
             TypedQuery.from_query(query,
               params: [],
               returns: [
                 %{name: "duplicate", type: :integer, nullable?: false},
                 %{name: "duplicate", type: :integer, nullable?: false}
               ]
             )
  end

  test "directory_from_query_directory converts typed queries and preserves errors" do
    first_query = %Query{
      file: "first.sql",
      starting_line: 1,
      name: "first",
      comment: [],
      content: "select name from users where id = $1"
    }

    duplicate_query = %Query{
      file: "duplicate.sql",
      starting_line: 1,
      name: "duplicate",
      comment: [],
      content: "select 1 as duplicate, 2 as duplicate"
    }

    parse_error = %Squirrelixir.Error.CannotReadFile{file: "missing.sql", reason: :enoent}

    query_directory = %QueryDirectory{
      directory: "lib/accounts/sql",
      queries: [duplicate_query, first_query],
      errors: [parse_error]
    }

    metadata = %{
      "first.sql" => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ],
      "duplicate.sql" => [
        params: [],
        returns: [
          %{name: "duplicate", type: :integer, nullable?: false},
          %{name: "duplicate", type: :integer, nullable?: false}
        ]
      ]
    }

    assert %TypedQueryDirectory{
             directory: "lib/accounts/sql",
             queries: [%TypedQuery{name: "first", params: [%Parameter{name: "id"}]}],
             errors: [^parse_error, %DuplicateReturnColumns{names: ["duplicate"]}]
           } = TypedQueryDirectory.from_query_directory(query_directory, metadata)
  end
end
