defmodule SquirrelixSQLTest do
  use ExUnit.Case, async: true

  alias Squirrelix.SQL

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

  test "infer_parameter_names infers names from INSERT column lists and VALUES" do
    sql = """
    insert into users (name, email)
    values ($1, $2)
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email"}
  end

  test "infer_parameter_names infers UPDATE SET names via equality" do
    sql = """
    update users
    set name = $1, email = $2
    where id = $3
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email", 3 => "id"}
  end

  test "infer_parameter_names handles quoted and table-qualified INSERT columns" do
    sql = ~s|insert into users (users.name, "special id") values ($1, $2)|

    assert SQL.infer_parameter_names(sql) == %{1 => "users_name", 2 => "special_id"}
  end

  test "infer_parameter_names pairs INSERT columns with placeholders amid literals" do
    sql = """
    insert into users (name, active, email)
    values ($1, true, $2)
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email"}
  end

  test "infer_parameter_names maps multi-row INSERT VALUES to the column list" do
    sql = """
    insert into users (name, email)
    values ($1, $2), ($3, $4)
    """

    assert SQL.infer_parameter_names(sql) == %{
             1 => "name",
             2 => "email",
             3 => "name",
             4 => "email"
           }
  end

  test "infer_parameter_names prefers equality names over INSERT column names" do
    sql = """
    insert into users (name, email)
    values ($1, $2)
    on conflict (email) do update
    set name = $1
    where users.id = $3
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email", 3 => "users_id"}
  end

  test "infer_parameter_names ignores INSERT comments when naming parameters" do
    sql = """
    insert into users (
      -- not_a_column
      name,
      email
    )
    values (
      /* $1 = fake */
      $1,
      $2
    )
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email"}
  end

  test "infer_parameter_names leaves non-placeholder INSERT values unnamed" do
    assert SQL.infer_parameter_names("insert into users (name) values (default)") == %{}
    assert SQL.infer_parameter_names("insert into users (name) select $1") == %{}
  end

  test "infer_parameter_names infers names from comparison operators" do
    sql = """
    select name from users
    where id > $1
      and created_at <= $2
      and status <> $3
      and score != $4
      and $5 < max_score
    """

    assert SQL.infer_parameter_names(sql) == %{
             1 => "id",
             2 => "created_at",
             3 => "status",
             4 => "score",
             5 => "max_score"
           }
  end

  test "infer_parameter_names infers names from LIKE and ILIKE" do
    sql = """
    select name from users
    where name like $1
      and email ilike $2
      and bio not like $3
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email", 3 => "bio"}
  end

  test "infer_parameter_names infers names from UPDATE SET column lists" do
    sql = """
    update users
    set (name, email) = ($1, $2)
    where id = $3
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email", 3 => "id"}
  end

  test "infer_parameter_names infers names from SET column lists with ROW" do
    sql = """
    update users
    set (name, email) = row($1, $2)
    where id = $3
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email", 3 => "id"}
  end

  test "infer_parameter_names infers ON CONFLICT DO UPDATE SET column lists" do
    sql = """
    insert into users (name, email)
    values ($1, $2)
    on conflict (email) do update
    set (name, active) = ($3, $4)
    where users.id = $5
    """

    assert SQL.infer_parameter_names(sql) == %{
             1 => "name",
             2 => "email",
             3 => "name",
             4 => "active",
             5 => "users_id"
           }
  end

  test "infer_parameter_names prefers equality over SET list and INSERT names" do
    sql = """
    insert into users (name, email)
    values ($1, $2)
    on conflict (email) do update
    set (name, email) = ($3, $1)
    where users.id = $3
    """

    assert SQL.infer_parameter_names(sql) == %{1 => "name", 2 => "email", 3 => "users_id"}
  end

  test "infer_parameter_names leaves IN, BETWEEN, and function-wrapped params unnamed" do
    assert SQL.infer_parameter_names("select * from users where id in ($1)") == %{}
    assert SQL.infer_parameter_names("select * from users where id between $1 and $2") == %{}
    assert SQL.infer_parameter_names("select * from users where lower(email) = $1") == %{}
    assert SQL.infer_parameter_names("insert into users values ($1, $2)") == %{}
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

  test "single_statement? allows a trailing semicolon and rejects batches" do
    assert SQL.single_statement?("select 1")
    assert SQL.single_statement?("select 1;")
    assert SQL.single_statement?("select ';';")
    assert SQL.single_statement?("-- note;\nselect 1")
    refute SQL.single_statement?("select 1; select 2")
    refute SQL.single_statement?("select 1; drop table users")
  end
end
