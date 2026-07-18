defmodule SquirrelixirProjectTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Project

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

    assert Project.root(nested) == :error
  end

  test "app reads the Mix application name" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), mixfile(:acorn_counter))

    assert Project.app(root) == {:ok, :acorn_counter}
  end

  test "app returns error when the Mix file cannot be evaluated" do
    root = tmp_dir()
    File.write!(Path.join(root, "mix.exs"), "not valid elixir")

    assert Project.app(root) == :error
  end

  test "source_roots returns conventional Elixir source roots" do
    root = tmp_dir()

    assert Project.source_roots(root) == [
             Path.join(root, "lib"),
             Path.join(root, "test"),
             Path.join(root, "dev")
           ]
  end

  defp tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "squirrelixir-project-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
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
