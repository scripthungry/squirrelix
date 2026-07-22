defmodule SquirrelixirSQLTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.SQL

  test "infer_parameter_names finds simple names on the left of equality" do
    sql = """
    with users as (select 1 as id, 'Louis' as name)
    select name from users where id = $1
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "id"}
  end

  test "infer_parameter_names finds simple names on the right of equality" do
    sql = """
    with users as (select 1 as id, 'Louis' as name)
    select name from users where $1 = id
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "id"}
  end

  test "infer_parameter_names handles table-qualified names" do
    sql = """
    with users as (select 1 as id, 'Louis' as name)
    select name from users where users.id = $1 and $2 = users.name
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "users_id", 2 => "users_name"}
  end

  test "infer_parameter_names handles quoted names" do
    sql = ~s|select name from users where users."special id" = $1 and $2 = "account name"|

    assert SQL.infer_parameter_names(sql) == %{1 => "users_special_id", 2 => "account_name"}
  end

  test "infer_parameter_names ignores comments and strings" do
    sql = """
    select name
    from users
    -- $1 = commented_id
    where $1 = '$1 = string_id'
    and $1 = name
    /* $2 = multiline_id */
    and email = $2
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email"}
  end

  test "infer_parameter_names keeps backslash-escaped quotes inside strings" do
    sql = "select * from users where note = 'not done \\' and $1 = fake' and email = $1"

    assert SQL.infer_parameter_names(sql) == %{1 => "email"}
  end

  test "infer_parameter_names ignores invalid inferred identifiers" do
    sql = ~s|select * from users where "123 invalid" = $1 and email = $2|

    assert SQL.infer_parameter_names(sql) == %{2 => "email"}
  end

  test "infer_parameter_names ignores nested block comments" do
    sql = """
    select name
    from users
    /* $1 = id /* $1 = id */ */
    where $1 = name
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name"}
  end

  test "infer_parameter_names leaves unmatched parameters unnamed" do
    assert SQL.infer_parameter_names("select * from users where $1 is null") == %{}
  end

  test "infer_parameter_names infers multiple arguments from one query" do
    sql = """
    with squirrel_user as (select 1 as squirrel_user_id, 'Louis' as name)
    select name
    from squirrel_user
    where $1 = squirrel_user_id
    and squirrel_user.name = $2
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "squirrel_user_id", 2 => "squirrel_user_name"}
  end

  test "infer_parameter_names infers quoted keyword-like column names" do
    sql = ~s|with wibble as (select 1 as "type") select * from wibble where $1 = "type"|

    assert SQL.infer_parameter_names(sql) == %{1 => "type"}
  end

  test "infer_parameter_names preserves very long argument names" do
    long_name = "this_is_a_very_very_very_long_parameter_name_test_aa"

    sql = """
    with wibble as (select 1 as #{long_name})
    select *
    from wibble
    where $1 = #{long_name}
    """

    assert SQL.infer_parameter_names(sql) == %{1 => long_name}
  end

  test "valid_identifier? accepts lowercase identifiers" do
    assert SQL.valid_identifier?("squirrel_user_name")
    refute SQL.valid_identifier?("123_invalid")
    refute SQL.valid_identifier?("NotValid")
  end

  test "similar_identifier proposes snake_case alternatives" do
    assert SQL.similar_identifier("not a valid name") == "not_a_valid_name"
    assert SQL.similar_identifier("123 invalid") == "invalid"
    assert SQL.similar_identifier("FindSquirrels") == "find_squirrels"
  end

  test "identifier_error reports invalid identifiers" do
    assert SQL.identifier_error("valid_name") == nil
    assert SQL.identifier_error("") == :empty
    assert SQL.identifier_error("123 invalid") == {:invalid_grapheme, 0, "1"}
    assert SQL.identifier_error("not a valid name") == {:invalid_grapheme, 3, " "}
  end
end
