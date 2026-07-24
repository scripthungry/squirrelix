defmodule SquirrelixTypedQueryTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Column
  alias Squirrelix.Error.DuplicateReturnColumns
  alias Squirrelix.Error.MissingQueryMetadata
  alias Squirrelix.Error.MissingQueryMetadataField
  alias Squirrelix.Error.QueryHasInvalidColumn
  alias Squirrelix.Parameter
  alias Squirrelix.Query
  alias Squirrelix.QueryDirectory
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypedQueryDirectory

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

  test "from_query infers table-qualified parameter names" do
    query = %Query{
      file: "find_user.sql",
      starting_line: 1,
      name: "find_user",
      comment: [],
      content:
        "select name from squirrel_user where squirrel_user.id = $1 and $2 = accounts.email"
    }

    assert {:ok,
            %TypedQuery{
              params: [
                %Parameter{index: 1, name: "squirrel_user_id", type: :integer},
                %Parameter{index: 2, name: "accounts_email", type: :string}
              ]
            }} =
             TypedQuery.from_query(query,
               params: [:integer, :string],
               returns: [%{name: "name", type: :string, nullable?: false}]
             )
  end

  test "from_query infers quoted table-qualified parameter names" do
    query = %Query{
      file: "find_user.sql",
      starting_line: 1,
      name: "find_user",
      comment: [],
      content: ~s(select name from squirrel_user where squirrel_user."special id" = $1)
    }

    assert {:ok,
            %TypedQuery{
              params: [%Parameter{index: 1, name: "squirrel_user_special_id", type: :integer}]
            }} =
             TypedQuery.from_query(query,
               params: [:integer],
               returns: [%{name: "name", type: :string, nullable?: false}]
             )
  end

  test "from_query normalizes Postgres type descriptors in metadata" do
    query = %Query{
      file: "find_user.sql",
      starting_line: 1,
      name: "find_user",
      comment: [],
      content: "select tags from users where id = $1"
    }

    assert {:ok,
            %TypedQuery{
              params: [%Parameter{type: :integer}],
              returns: [%Column{name: "tags", type: {:list, :string}, nullable?: false}]
            }} =
             TypedQuery.from_query(query,
               params: [{:postgres, "int4"}],
               returns: [
                 %{name: "tags", type: %{postgres: "text", array_dimensions: 1}, nullable?: false}
               ]
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

  test "from_query rejects multiple duplicate return column names" do
    query = %Query{
      file: "duplicate.sql",
      starting_line: 1,
      name: "duplicate",
      comment: [],
      content:
        "select 1 as duplicate_1, 2 as duplicate_2, 3 as not_duplicate, 4 as duplicate_1, 5 as duplicate_2"
    }

    assert {:error, %DuplicateReturnColumns{names: ["duplicate_1", "duplicate_2"]}} =
             TypedQuery.from_query(query,
               params: [],
               returns: [
                 %{name: "duplicate_1", type: :integer, nullable?: false},
                 %{name: "duplicate_2", type: :integer, nullable?: false},
                 %{name: "not_duplicate", type: :integer, nullable?: false},
                 %{name: "duplicate_1", type: :integer, nullable?: false},
                 %{name: "duplicate_2", type: :integer, nullable?: false}
               ]
             )
  end

  test "from_query rejects invalid return column names" do
    query = %Query{
      file: "invalid_column.sql",
      starting_line: 1,
      name: "invalid_column",
      comment: [],
      content: ~s|select name as "not a valid name" from squirrel|
    }

    assert {:error,
            %QueryHasInvalidColumn{
              file: "invalid_column.sql",
              starting_line: 1,
              content: ~s|select name as "not a valid name" from squirrel|,
              column_name: "not a valid name",
              suggested_name: "not_a_valid_name",
              reason: {:invalid_grapheme, 3, " "}
            }} =
             TypedQuery.from_query(query,
               params: [],
               returns: [%{name: "not a valid name", type: :string, nullable?: false}]
             )
  end

  test "from_query invalid column errors format with query context" do
    query = %Query{
      file: "invalid_column.sql",
      starting_line: 1,
      name: "invalid_column",
      comment: [],
      content: ~s|select name as "not a valid name" from squirrel|
    }

    assert {:error, error} =
             TypedQuery.from_query(query,
               params: [],
               returns: [%{name: "not a valid name", type: :string, nullable?: false}]
             )

    formatted = Squirrelix.Error.format(error)
    assert formatted =~ "Error: Column with invalid name"
    assert formatted =~ "invalid_column.sql"
    assert formatted =~ "maybe try `not_a_valid_name`"
    assert formatted =~ "Hint: A column name must start with a lowercase letter"
  end

  test "from_query duplicate column errors format with query context" do
    query = %Query{
      file: "duplicate.sql",
      starting_line: 1,
      name: "duplicate",
      comment: [],
      content: "select 1 as duplicate, 2 as duplicate"
    }

    assert {:error, error} =
             TypedQuery.from_query(query,
               params: [],
               returns: [
                 %{name: "duplicate", type: :integer, nullable?: false},
                 %{name: "duplicate", type: :integer, nullable?: false}
               ]
             )

    formatted = Squirrelix.Error.format(error)
    assert formatted =~ "Error: Duplicate names"
    assert formatted =~ "sharing the same name: `duplicate`"
  end

  test "from_query infers multiple parameter names" do
    query = %Query{
      file: "multiple.sql",
      starting_line: 1,
      name: "multiple",
      comment: [],
      content: """
      with squirrel_user as (select 1 as squirrel_user_id, 'Louis' as name)
      select name
      from squirrel_user
      where $1 = squirrel_user_id
      and squirrel_user.name = $2
      """
    }

    assert {:ok,
            %TypedQuery{
              params: [
                %Parameter{index: 1, name: "squirrel_user_id", type: :integer},
                %Parameter{index: 2, name: "squirrel_user_name", type: :string}
              ]
            }} =
             TypedQuery.from_query(query,
               params: [:integer, :string],
               returns: [%{name: "name", type: :string, nullable?: false}]
             )
  end

  test "resolve_parameter_names renames arguments that would shadow decoder helpers" do
    params = [%Parameter{index: 1, name: "uuid_decoder", type: :string}]

    assert TypedQuery.resolve_parameter_names(params) == ["uuid_decoder_1"]
  end

  test "resolve_parameter_names renames inferred conn argument" do
    params = [%Parameter{index: 1, name: "conn", type: :integer}]

    assert TypedQuery.resolve_parameter_names(params) == ["conn_1"]
  end

  test "from_query renames inferred conn argument in generated params" do
    query = %Query{
      file: "shadow_conn.sql",
      starting_line: 1,
      name: "shadow_conn",
      comment: [],
      content: """
      with wibble as (select 1 as conn)
      select conn
      from wibble
      where $1 = conn
      """
    }

    assert {:ok, %TypedQuery{params: params}} =
             TypedQuery.from_query(query,
               params: [:integer],
               returns: [%{name: "conn", type: :integer, nullable?: false}]
             )

    assert TypedQuery.resolve_parameter_names(params) == ["conn_1"]
  end

  test "resolve_parameter_names deconflicts duplicate inferred names" do
    params = [
      %Parameter{index: 1, name: "number", type: :integer},
      %Parameter{index: 2, name: "number", type: :integer}
    ]

    assert TypedQuery.resolve_parameter_names(params) == ["number", "number_1"]
  end

  test "resolve_parameter_names deconflicts fallback argument names" do
    params = [
      %Parameter{index: 1, name: nil, type: :integer},
      %Parameter{index: 2, name: "arg_1", type: :integer}
    ]

    assert TypedQuery.resolve_parameter_names(params) == ["arg_1", "arg_1_1"]
  end

  test "resolve_parameter_names preserves very long argument names" do
    long_name = "this_is_a_very_very_very_long_parameter_name_test_aa"
    params = [%Parameter{index: 1, name: long_name, type: :integer}]

    assert TypedQuery.resolve_parameter_names(params) == [long_name]
  end

  test "resolve_parameter_names avoids Elixir reserved argument names" do
    params = [
      %Parameter{index: 1, name: "type", type: :integer},
      %Parameter{index: 2, name: "fn", type: :integer}
    ]

    assert TypedQuery.resolve_parameter_names(params) == ["type", "fn_"]
  end

  test "from_query resolves parameter names end-to-end for duplicate inferred names" do
    query = %Query{
      file: "duplicate_params.sql",
      starting_line: 1,
      name: "duplicate_params",
      comment: [],
      content: """
      with wibble as (select 1 as number)
      select *
      from wibble
      where $1 = number
      and $2 = number
      """
    }

    assert {:ok, %TypedQuery{params: params}} =
             TypedQuery.from_query(query,
               params: [:integer, :integer],
               returns: [%{name: "number", type: :integer, nullable?: false}]
             )

    assert TypedQuery.resolve_parameter_names(params) == ["number", "number_1"]
  end

  test "from_query rejects metadata missing required fields" do
    query = %Query{
      file: "incomplete.sql",
      starting_line: 1,
      name: "incomplete",
      comment: [],
      content: "select 1"
    }

    assert TypedQuery.from_query(query, params: []) ==
             {:error, %MissingQueryMetadataField{file: "incomplete.sql", field: :returns}}

    assert TypedQuery.from_query(query, returns: []) ==
             {:error, %MissingQueryMetadataField{file: "incomplete.sql", field: :params}}
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

    parse_error = %Squirrelix.Error.CannotReadFile{file: "missing.sql", reason: :enoent}

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

  test "directory_from_query_directory reports missing query metadata" do
    query = %Query{
      file: "missing_metadata.sql",
      starting_line: 1,
      name: "missing_metadata",
      comment: [],
      content: "select 1"
    }

    query_directory = %QueryDirectory{
      directory: "lib/accounts/sql",
      queries: [query],
      errors: []
    }

    assert %TypedQueryDirectory{
             directory: "lib/accounts/sql",
             queries: [],
             errors: [%MissingQueryMetadata{file: "missing_metadata.sql"}]
           } = TypedQueryDirectory.from_query_directory(query_directory, %{})
  end

  test "directory_from_query_directory preserves incomplete metadata errors" do
    query = %Query{
      file: "incomplete.sql",
      starting_line: 1,
      name: "incomplete",
      comment: [],
      content: "select 1"
    }

    query_directory = %QueryDirectory{
      directory: "lib/accounts/sql",
      queries: [query],
      errors: []
    }

    assert %TypedQueryDirectory{
             queries: [],
             errors: [%MissingQueryMetadataField{file: "incomplete.sql", field: :returns}]
           } =
             TypedQueryDirectory.from_query_directory(query_directory, %{
               query.file => [params: []]
             })
  end
end
