defmodule SquirrelixOutputTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Error.CannotOverwriteFile
  alias Squirrelix.Error.CannotWriteFile
  alias Squirrelix.Error.OutdatedFile
  alias Squirrelix.Output

  @generated_content """
  //// > 🐿️ This module was generated automatically using Squirrelix
  defmodule Generated do
  end
  """

  test "safe_write writes a new file and creates parent directories" do
    path = Path.join(tmp_dir(), "nested/sql.ex")

    assert Output.safe_write(path, @generated_content) == :ok
    assert File.read!(path) == @generated_content
  end

  test "safe_write overwrites likely generated files" do
    path = write_file("sql.ex", @generated_content)
    content = "defmodule Sql do\ndef all do\n[]\nend\nend\n"

    assert Output.safe_write(path, content) == :ok

    assert File.read!(path) == """
           defmodule Sql do
             def all do
               []
             end
           end
           """
  end

  test "safe_write overwrites empty files" do
    path = write_file("sql.ex", "  \n\t")
    content = "defmodule Sql do\ndef all do\n[]\nend\nend\n"

    assert Output.safe_write(path, content) == :ok

    assert File.read!(path) == """
           defmodule Sql do
             def all do
               []
             end
           end
           """
  end

  test "safe_write formats Elixir files before writing" do
    path = Path.join(tmp_dir(), "sql.ex")
    content = "defmodule Sql do\ndef all do\n:ok\nend\nend\n"

    assert Output.safe_write(path, content) == :ok

    assert File.read!(path) == """
           defmodule Sql do
             def all do
               :ok
             end
           end
           """
  end

  test "safe_write does not format non-Elixir files" do
    path = Path.join(tmp_dir(), "query.sql")
    content = "select   *\nfrom users"

    assert Output.safe_write(path, content) == :ok
    assert File.read!(path) == content
  end

  test "safe_write refuses to overwrite human-written files" do
    path = write_file("sql.ex", "defmodule HandWritten do\nend\n")

    assert Output.safe_write(path, @generated_content) ==
             {:error, %CannotOverwriteFile{file: path}}

    assert File.read!(path) == "defmodule HandWritten do\nend\n"
  end

  test "safe_write returns a write error when target cannot be written" do
    path = tmp_dir()

    assert {:error, %CannotWriteFile{file: ^path, reason: :eisdir}} =
             Output.safe_write(path, @generated_content)
  end

  test "check_file returns ok when output matches ignoring comments and whitespace" do
    path = write_file("sql.ex", "# Generated\ndefmodule Sql do\n  def all(), do: []\nend\n")
    expected = "defmodule Sql do\ndef all(), do: []\nend\n"

    assert Output.check_file(path, expected) == :ok
  end

  test "check_file returns an outdated-file error when output differs" do
    path = write_file("sql.ex", "defmodule Sql do\n  def all(), do: []\nend\n")
    expected = "defmodule Sql do\n  def all(), do: [1]\nend\n"

    assert Output.check_file(path, expected) == {:error, %OutdatedFile{file: path}}
  end

  test "check_file returns a read error when output is missing" do
    path = Path.join(tmp_dir(), "missing.ex")

    assert {:error, %Squirrelix.Error.CannotReadFile{file: ^path, reason: :enoent}} =
             Output.check_file(path, @generated_content)
  end

  defp write_file(file_name, content) do
    dir = tmp_dir()
    path = Path.join(dir, file_name)
    File.write!(path, content)
    path
  end

  defp tmp_dir do
    Squirrelix.TestSupport.tmp_dir!("squirr_elix-output")
  end
end
