defmodule SquirrelixProjectTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Project

  test "root finds the nearest Mix project root by walking up from a nested path" do
    root = tmp_dir()
    nested = Path.join(root, "lib/nested/path")

    File.mkdir_p!(nested)
    File.write!(Path.join(root, "mix.exs"), mixfile(:acorn_counter))

    assert Project.root(nested) == {:ok, root}
  end

  test "root returns error when no Mix project can be found" do
    root = tmp_dir()
    nested = Path.join(root, "lib/nested/path")

    File.mkdir_p!(nested)

    assert Project.root(nested) == {:error, :not_found}
  end

  test "app reads the Mix application name" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), mixfile(:acorn_counter))

    assert Project.app(root) == {:ok, :acorn_counter}
  end

  test "app returns error when the Mix file cannot be evaluated" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), "not valid elixir")

    assert Project.app(root) == {:error, :invalid_mixfile}
  end

  test "source_roots returns conventional Elixir source roots" do
    root = tmp_dir()

    assert Project.source_roots(root) == [
             Path.join(root, "lib"),
             Path.join(root, "test"),
             Path.join(root, "dev")
           ]
  end

  test "module_for_sql_directory derives an app-namespaced module from lib path" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), mixfile(:acorn_counter))

    assert Project.module_for_sql_directory(root, Path.join(root, "lib/accounts/sql")) ==
             {:ok, AcornCounter.Accounts.SQL}
  end

  test "module_for_sql_directory dedups Phoenix-style leading app segment" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), mixfile(:my_app))

    assert Project.module_for_sql_directory(root, Path.join(root, "lib/my_app/accounts/sql")) ==
             {:ok, MyApp.Accounts.SQL}

    assert Project.module_for_sql_directory(root, Path.join(root, "lib/my_app/sql")) ==
             {:ok, MyApp.SQL}
  end

  test "module_for_sql_directory keeps nested segments that match app name only at the front" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), mixfile(:my_app))

    assert Project.module_for_sql_directory(
             root,
             Path.join(root, "lib/my_app/my_app/sql")
           ) == {:ok, MyApp.MyApp.SQL}
  end

  test "module_for_sql_directory derives an app-namespaced module from test path" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), mixfile(:acorn_counter))

    assert Project.module_for_sql_directory(root, Path.join(root, "test/support/sql")) ==
             {:ok, AcornCounter.Support.SQL}
  end

  test "module_for_sql_directory returns error for paths outside source roots" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), mixfile(:acorn_counter))

    assert Project.module_for_sql_directory(root, Path.join(root, "priv/sql")) ==
             {:error, :invalid_sql_directory}
  end

  defp tmp_dir do
    Squirrelix.TestSupport.tmp_dir!("squirr_elix-project")
  end

  defp mixfile(app) do
    """
    defmodule TempProject.MixProject do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0"]
      end
    end
    """
  end
end
