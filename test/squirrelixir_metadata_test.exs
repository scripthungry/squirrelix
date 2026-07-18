defmodule SquirrelixirMetadataTest do
  use ExUnit.Case, async: true

  alias Squirrelixir.Metadata

  test "from_file loads query metadata and expands relative query paths from the project root" do
    root = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-metadata")
    metadata_file = Path.join(root, "squirrelixir.exs")

    File.write!(metadata_file, """
    %{
      "lib/accounts/sql/find_account.sql" => [
        params: [:integer],
        returns: [%{name: "name", type: :string, nullable?: false}]
      ]
    }
    """)

    assert Metadata.from_file(metadata_file, root: root) ==
             {:ok,
              %{
                Path.join(root, "lib/accounts/sql/find_account.sql") => [
                  params: [:integer],
                  returns: [%{name: "name", type: :string, nullable?: false}]
                ]
              }}
  end

  test "from_file keeps absolute query paths unchanged" do
    root = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-metadata")
    metadata_file = Path.join(root, "squirrelixir.exs")
    query_file = Path.join(root, "lib/accounts/sql/find_account.sql")

    File.write!(metadata_file, inspect(%{query_file => [params: [], returns: []]}))

    assert Metadata.from_file(metadata_file, root: root) ==
             {:ok, %{query_file => [params: [], returns: []]}}
  end

  test "from_file reports unreadable files" do
    file = Path.join(Squirrelixir.TestSupport.tmp_dir!("squirrelixir-metadata"), "missing.exs")

    assert Metadata.from_file(file, root: Path.dirname(file)) ==
             {:error, %Squirrelixir.Error.CannotReadFile{file: file, reason: :enoent}}
  end

  test "from_file reports metadata files that do not return a map" do
    root = Squirrelixir.TestSupport.tmp_dir!("squirrelixir-metadata")
    metadata_file = Path.join(root, "squirrelixir.exs")

    File.write!(metadata_file, ":not_a_map")

    assert Metadata.from_file(metadata_file, root: root) ==
             {:error,
              %Squirrelixir.Error.InvalidQueryMetadataFile{
                file: metadata_file,
                reason: :not_a_map
              }}
  end
end
