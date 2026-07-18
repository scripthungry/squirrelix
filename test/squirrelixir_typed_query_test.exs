defmodule SquirrelixirTypedQueryTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Column
  alias Squirrelixir.Error.DuplicateReturnColumns
  alias Squirrelixir.Parameter
  alias Squirrelixir.Query
  alias Squirrelixir.TypedQuery

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
end
