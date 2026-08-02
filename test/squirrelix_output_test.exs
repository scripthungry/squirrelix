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

  test "prepare_write format: false leaves Elixir content unchanged" do
    path = Path.join(tmp_dir(), "sql.ex")
    content = "defmodule Sql do\ndef all do\n:ok\nend\nend\n"

    assert {:ok, prepared} = Output.prepare_write(path, content, format: false)
    assert prepared.content == content
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

  test "safe_write leaves no temp artifacts after a successful write" do
    path = Path.join(tmp_dir(), "sql.ex")

    assert Output.safe_write(path, @generated_content) == :ok
    assert File.read!(path) == @generated_content
    refute File.exists?(path <> ".squirrelix.tmp")
    refute File.exists?(path <> ".squirrelix.bak")
  end

  test "commit_writes rolls back earlier files when a later rename fails" do
    dir = tmp_dir()
    first = Path.join(dir, "accounts/sql.ex")
    second = Path.join(dir, "billing/sql.ex")
    File.mkdir_p!(Path.dirname(first))
    File.mkdir_p!(Path.dirname(second))

    File.write!(first, @generated_content)
    File.write!(second, @generated_content)

    new_content = """
    //// > 🐿️ This module was generated automatically using Squirrelix
    defmodule Updated do
    end
    """

    assert {:ok, prepared_first} = Output.prepare_write(first, new_content)
    assert {:ok, prepared_second} = Output.prepare_write(second, new_content)

    assert :ok = Output.stage_writes([prepared_first, prepared_second])

    # Sabotage the second staged temp so finalize fails after the first rename.
    File.rm!(second <> ".squirrelix.tmp")

    assert {:error, %CannotWriteFile{file: ^second, reason: :enoent}} =
             Output.finalize_writes([prepared_first, prepared_second])

    assert File.read!(first) == @generated_content
    assert File.read!(second) == @generated_content
    refute File.exists?(first <> ".squirrelix.tmp")
    refute File.exists?(second <> ".squirrelix.tmp")
    refute File.exists?(first <> ".squirrelix.bak")
    refute File.exists?(second <> ".squirrelix.bak")
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
