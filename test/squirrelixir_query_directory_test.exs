defmodule SquirrelixirQueryDirectoryTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Error.QueryFileHasInvalidName
  alias Squirrelixir.Query
  alias Squirrelixir.QueryDirectory

  test "from_files parses queries and keeps errors for a SQL directory" do
    dir = tmp_dir()
    valid = write_sql(dir, "find_squirrels.sql", "select * from squirrels")
    invalid = write_sql(dir, "01 invalid.sql", "select 1")

    assert %QueryDirectory{
             directory: ^dir,
             queries: [
               %Query{file: ^valid, name: "find_squirrels", content: "select * from squirrels"}
             ],
             errors: [
               %QueryFileHasInvalidName{file: ^invalid, suggested_name: "invalid"}
             ]
           } = QueryDirectory.from_files(dir, [invalid, valid])
  end

  test "from_discovered_files returns sorted query directories" do
    root = tmp_dir()
    accounts_dir = Path.join(root, "lib/accounts/sql")
    billing_dir = Path.join(root, "lib/billing/sql")

    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(billing_dir)
    account_query = write_sql(accounts_dir, "find_account.sql", "select 1")
    billing_query = write_sql(billing_dir, "find_invoice.sql", "select 2")

    discovered = %{
      billing_dir => [billing_query],
      accounts_dir => [account_query]
    }

    assert [
             %QueryDirectory{directory: ^accounts_dir, queries: [%Query{name: "find_account"}]},
             %QueryDirectory{directory: ^billing_dir, queries: [%Query{name: "find_invoice"}]}
           ] = QueryDirectory.from_discovered_files(discovered)
  end

  defp write_sql(dir, file_name, content) do
    path = Path.join(dir, file_name)
    File.write!(path, content)
    path
  end

  defp tmp_dir do
    Squirrelixir.TestSupport.tmp_dir!("squirrelixir-query-directory")
  end
end
