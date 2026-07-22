defmodule SquirrElixMetadataTest do
  use ExUnit.Case, async: true

  alias SquirrElix.Metadata

  test "from_file loads query metadata and expands relative query paths from the project root" do
    root = SquirrElix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")

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
    root = SquirrElix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")
    query_file = Path.join(root, "lib/accounts/sql/find_account.sql")

    File.write!(metadata_file, inspect(%{query_file => [params: [], returns: []]}))

    assert Metadata.from_file(metadata_file, root: root) ==
             {:ok, %{query_file => [params: [], returns: []]}}
  end

  test "from_file reports unreadable files" do
    file = Path.join(SquirrElix.TestSupport.tmp_dir!("squirr_elix-metadata"), "missing.exs")

    assert Metadata.from_file(file, root: Path.dirname(file)) ==
             {:error, %SquirrElix.Error.CannotReadFile{file: file, reason: :enoent}}
  end

  test "from_file expands dot-relative query paths from the project root" do
    root = SquirrElix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")

    File.write!(metadata_file, """
    %{
      "./lib/accounts/sql/find_account.sql" => [
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

  test "from_file reports syntax errors in metadata files" do
    root = SquirrElix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")

    File.write!(metadata_file, "%{")

    assert {:error, %SquirrElix.Error.InvalidQueryMetadataFile{file: ^metadata_file, reason: _}} =
             Metadata.from_file(metadata_file, root: root)
  end

  test "from_file reports metadata files that do not return a map" do
    root = SquirrElix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")

    File.write!(metadata_file, ":not_a_map")

    assert Metadata.from_file(metadata_file, root: root) ==
             {:error,
              %SquirrElix.Error.InvalidQueryMetadataFile{
                file: metadata_file,
                reason: :not_a_map
              }}
  end
end
