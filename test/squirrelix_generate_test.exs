defmodule SquirrelixGenerateTest do
  use ExUnit.Case, async: true

  alias Squirrelix.CodegenCheckSummary
  alias Squirrelix.CodegenSummary

  test "generate discovers SQL files, writes generated modules, and returns a summary" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts where id = $1")

    metadata = %{
      query_file => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert Squirrelix.generate(root, metadata, version: "v-test") == %CodegenSummary{
             generated_count: 1,
             errors: [],
             status: :ok
           }

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~
             "defmodule AcornCounter.Accounts.SQL do"
  end

  test "generate accepts a query inferrer instead of static metadata" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    File.write!(
      Path.join(sql_directory, "find_account.sql"),
      "select name from accounts where id = $1"
    )

    inferrer = fn _query ->
      {:ok,
       [
         params: [{:postgres, "int4"}],
         returns: [%{name: "name", type: {:postgres, "text"}, nullable?: false}]
       ]}
    end

    assert Squirrelix.generate(root, inferrer, version: "v-test") == %CodegenSummary{
             generated_count: 1,
             errors: [],
             status: :ok
           }

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "required(:name) => String.t()"
  end

  test "generate reports directory errors without writing generated modules" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "01 invalid.sql")
    File.write!(query_file, "select 1")

    assert %CodegenSummary{
             generated_count: 0,
             errors: [{^sql_directory, [_error]}],
             status: :error
           } = Squirrelix.generate(root, %{}, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
  end

  test "generate reports missing metadata without writing generated modules" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts")

    assert %CodegenSummary{
             generated_count: 0,
             errors: [
               {^sql_directory, [%Squirrelix.Error.MissingQueryMetadata{file: ^query_file}]}
             ],
             status: :error
           } = Squirrelix.generate(root, %{}, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
  end

  test "check discovers SQL files and reports generated modules are current" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts where id = $1")

    metadata = %{
      query_file => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert Squirrelix.generate(root, metadata, version: "v-test").status == :ok

    assert Squirrelix.check(root, metadata, version: "v-test") == %CodegenCheckSummary{
             checked_count: 1,
             errors: [],
             status: :ok
           }
  end

  test "check reports outdated generated modules when query output changes" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts where id = $1")

    metadata = %{
      query_file => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert Squirrelix.generate(root, metadata, version: "v-test").status == :ok

    File.write!(query_file, "select email from accounts where id = $1")

    assert %CodegenCheckSummary{
             checked_count: 0,
             errors: [{^sql_directory, %Squirrelix.Error.OutdatedFile{}}],
             status: :error
           } = Squirrelix.check(root, metadata, version: "v-test")
  end

  test "generate refuses to overwrite human-written sql.ex files" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    output_file = Path.join(root, "lib/accounts/sql.ex")

    File.write!(query_file, "select name from accounts where id = $1")
    File.write!(output_file, "defmodule HandWritten do\nend\n")

    metadata = %{
      query_file => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert %CodegenSummary{
             generated_count: 0,
             errors: [
               {^sql_directory, %Squirrelix.Error.CannotOverwriteFile{file: ^output_file}}
             ],
             status: :error
           } = Squirrelix.generate(root, metadata, version: "v-test")

    assert File.read!(output_file) == "defmodule HandWritten do\nend\n"
  end

  test "generate writes queries in alphabetical order by source file" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    last_query = Path.join(sql_directory, "z_last.sql")
    first_query = Path.join(sql_directory, "a_first.sql")

    File.write!(last_query, "select 1 as wibble")
    File.write!(first_query, "select 2 as wibble")

    metadata = %{
      last_query => [
        params: [],
        returns: [%{name: "wibble", type: :integer, nullable?: false}]
      ],
      first_query => [
        params: [],
        returns: [%{name: "wibble", type: :integer, nullable?: false}]
      ]
    }

    assert Squirrelix.generate(root, metadata, version: "v-test").status == :ok

    output = File.read!(Path.join(root, "lib/accounts/sql.ex"))
    first_pos = output |> :binary.match("def a_first(") |> elem(0)
    last_pos = output |> :binary.match("def z_last(") |> elem(0)

    assert first_pos < last_pos
  end

  test "check reports missing generated modules without writing them" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query_file = Path.join(sql_directory, "find_account.sql")
    File.write!(query_file, "select name from accounts")

    metadata = %{
      query_file => [
        params: [],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert %CodegenCheckSummary{
             checked_count: 0,
             errors: [{^sql_directory, %Squirrelix.Error.CannotReadFile{reason: :enoent}}],
             status: :error
           } = Squirrelix.check(root, metadata, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
  end

  test "generate refuses all writes when any sql directory has query errors" do
    root = tmp_project(:acorn_counter)
    good_dir = Path.join(root, "lib/accounts/sql")
    bad_dir = Path.join(root, "lib/billing/sql")
    File.mkdir_p!(good_dir)
    File.mkdir_p!(bad_dir)

    good_query = Path.join(good_dir, "find_account.sql")
    bad_query = Path.join(bad_dir, "01 invalid.sql")

    File.write!(good_query, "select name from accounts where id = $1")
    File.write!(bad_query, "select 1")

    metadata = %{
      good_query => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert %CodegenSummary{
             generated_count: 0,
             errors: [{^bad_dir, [_error]}],
             status: :error
           } = Squirrelix.generate(root, metadata, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
    refute File.exists?(Path.join(root, "lib/billing/sql.ex"))
  end

  test "generate refuses all writes when any directory cannot be overwritten" do
    root = tmp_project(:acorn_counter)
    good_dir = Path.join(root, "lib/accounts/sql")
    bad_dir = Path.join(root, "lib/billing/sql")
    File.mkdir_p!(good_dir)
    File.mkdir_p!(bad_dir)

    good_query = Path.join(good_dir, "find_account.sql")
    bad_query = Path.join(bad_dir, "find_invoice.sql")
    good_output = Path.join(root, "lib/accounts/sql.ex")
    bad_output = Path.join(root, "lib/billing/sql.ex")

    File.write!(good_query, "select name from accounts where id = $1")
    File.write!(bad_query, "select total from invoices where id = $1")
    File.write!(bad_output, "defmodule HandWritten do\nend\n")

    metadata = %{
      good_query => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ],
      bad_query => [
        params: [:integer],
        returns: [%{name: "total", type: :integer, nullable?: false}]
      ]
    }

    assert %CodegenSummary{
             generated_count: 0,
             errors: [
               {^bad_dir, %Squirrelix.Error.CannotOverwriteFile{file: ^bad_output}}
             ],
             status: :error
           } = Squirrelix.generate(root, metadata, version: "v-test")

    refute File.exists?(good_output)
    assert File.read!(bad_output) == "defmodule HandWritten do\nend\n"
  end

  test "generate refuses all writes when any directory is missing metadata" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    billing_dir = Path.join(root, "lib/billing/sql")
    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(billing_dir)

    accounts_query = Path.join(accounts_dir, "find_account.sql")
    billing_query = Path.join(billing_dir, "find_invoice.sql")

    File.write!(accounts_query, "select name from accounts where id = $1")
    File.write!(billing_query, "select total from invoices where id = $1")

    metadata = %{
      accounts_query => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }

    assert %CodegenSummary{
             generated_count: 0,
             errors: [
               {^billing_dir, [%Squirrelix.Error.MissingQueryMetadata{file: ^billing_query}]}
             ],
             status: :error
           } = Squirrelix.generate(root, metadata, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
    refute File.exists?(Path.join(root, "lib/billing/sql.ex"))
  end

  test "check fails globally when any sql directory has query errors" do
    root = tmp_project(:acorn_counter)
    good_dir = Path.join(root, "lib/accounts/sql")
    bad_dir = Path.join(root, "lib/billing/sql")
    File.mkdir_p!(good_dir)
    File.mkdir_p!(bad_dir)

    good_query = Path.join(good_dir, "find_account.sql")
    bad_query = Path.join(bad_dir, "find_invoice.sql")

    File.write!(good_query, "select name from accounts where id = $1")
    File.write!(bad_query, "select total from invoices where id = $1")

    good_metadata = [
      params: [:integer],
      returns: [%{name: "name", type: :string, nullable?: false}]
    ]

    bad_metadata = [
      params: [:integer],
      returns: [%{name: "total", type: :integer, nullable?: false}]
    ]

    assert Squirrelix.generate(
             root,
             %{good_query => good_metadata, bad_query => bad_metadata},
             version: "v-test"
           ).status == :ok

    assert %CodegenCheckSummary{
             checked_count: 1,
             errors: [
               {^bad_dir, [%Squirrelix.Error.MissingQueryMetadata{file: ^bad_query}]}
             ],
             status: :error
           } = Squirrelix.check(root, %{good_query => good_metadata}, version: "v-test")

    assert File.exists?(Path.join(root, "lib/accounts/sql.ex"))
    assert File.exists?(Path.join(root, "lib/billing/sql.ex"))
  end

  test "generate reports every directory error and writes nothing" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    billing_dir = Path.join(root, "lib/billing/sql")
    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(billing_dir)

    accounts_query = Path.join(accounts_dir, "find_account.sql")
    billing_query = Path.join(billing_dir, "find_invoice.sql")

    File.write!(accounts_query, "select name from accounts where id = $1")
    File.write!(billing_query, "select total from invoices where id = $1")

    assert %CodegenSummary{
             generated_count: 0,
             errors: [
               {^accounts_dir, [%Squirrelix.Error.MissingQueryMetadata{file: ^accounts_query}]},
               {^billing_dir, [%Squirrelix.Error.MissingQueryMetadata{file: ^billing_query}]}
             ],
             status: :error
           } = Squirrelix.generate(root, %{}, version: "v-test")

    refute File.exists?(Path.join(root, "lib/accounts/sql.ex"))
    refute File.exists?(Path.join(root, "lib/billing/sql.ex"))
  end

  test "generate writes every directory when all queries succeed" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    billing_dir = Path.join(root, "lib/billing/sql")
    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(billing_dir)

    accounts_query = Path.join(accounts_dir, "find_account.sql")
    billing_query = Path.join(billing_dir, "find_invoice.sql")

    File.write!(accounts_query, "select name from accounts where id = $1")
    File.write!(billing_query, "select total from invoices where id = $1")

    metadata = %{
      accounts_query => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ],
      billing_query => [
        params: [:integer],
        returns: [%{name: "total", type: :integer, nullable?: false}]
      ]
    }

    assert Squirrelix.generate(root, metadata, version: "v-test") == %CodegenSummary{
             generated_count: 2,
             errors: [],
             status: :ok
           }

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~
             "defmodule AcornCounter.Accounts.SQL do"

    assert File.read!(Path.join(root, "lib/billing/sql.ex")) =~
             "defmodule AcornCounter.Billing.SQL do"
  end

  defp tmp_project(app) do
    path = Squirrelix.TestSupport.tmp_dir!("squirr_elix-generate")

    File.write!(Path.join(path, "mix.exs"), """
    defmodule TempProject.MixProject do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0"]
      end
    end
    """)

    path
  end
end
