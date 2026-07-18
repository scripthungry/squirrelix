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

  test "infer_parameter_names leaves unmatched parameters unnamed" do
    assert SQL.infer_parameter_names("select * from users where $1 is null") == %{}
  end
end
