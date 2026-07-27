defmodule SquirrelixMetadataTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Column
  alias Squirrelix.Metadata
  alias Squirrelix.Parameter
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypedQueryDirectory

  test "from_file loads query metadata and expands relative query paths from the project root" do
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
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
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")
    query_file = Path.join(root, "lib/accounts/sql/find_account.sql")

    File.write!(metadata_file, inspect(%{query_file => [params: [], returns: []]}))

    assert Metadata.from_file(metadata_file, root: root) ==
             {:ok, %{query_file => [params: [], returns: []]}}
  end

  test "from_file reports unreadable files" do
    file = Path.join(Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata"), "missing.exs")

    assert Metadata.from_file(file, root: Path.dirname(file)) ==
             {:error, %Squirrelix.Error.CannotReadFile{file: file, reason: :enoent}}
  end

  test "from_file expands dot-relative query paths from the project root" do
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
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
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")

    File.write!(metadata_file, "%{")

    assert {:error, %Squirrelix.Error.InvalidQueryMetadataFile{file: ^metadata_file, reason: _}} =
             Metadata.from_file(metadata_file, root: root)
  end

  test "from_file reports metadata files that do not return a map" do
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
    metadata_file = Path.join(root, "squirr_elix.exs")

    File.write!(metadata_file, ":not_a_map")

    assert Metadata.from_file(metadata_file, root: root) ==
             {:error,
              %Squirrelix.Error.InvalidQueryMetadataFile{
                file: metadata_file,
                reason: :not_a_map
              }}
  end

  test "from_typed_directories builds absolute-path metadata from typed queries" do
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
    query_file = Path.join(root, "lib/accounts/sql/find_account.sql")

    directories = [
      %TypedQueryDirectory{
        directory: Path.join(root, "lib/accounts/sql"),
        queries: [
          %TypedQuery{
            file: query_file,
            starting_line: 1,
            name: "find_account",
            comment: [],
            content: "select name from accounts where id = $1",
            params: [%Parameter{index: 1, name: "id", type: :integer}],
            returns: [
              %Column{name: "name", type: :string, nullable?: false},
              %Column{name: "tags", type: {:list, :string}, nullable?: true}
            ]
          }
        ],
        errors: []
      }
    ]

    assert Metadata.from_typed_directories(directories) == %{
             query_file => [
               params: [:integer],
               returns: [
                 %{name: "name", type: :string, nullable?: false},
                 %{name: "tags", type: {:list, :string}, nullable?: true}
               ]
             ]
           }
  end

  test "to_file writes reloadable relative-path metadata and round-trips through from_file" do
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
    query_file = Path.join(root, "lib/accounts/sql/find_account.sql")
    metadata_file = Path.join(root, "squirr_elix.exs")

    metadata = %{
      query_file => [
        params: [:integer, {:list, :string}],
        returns: [
          %{name: "name", type: :string, nullable?: false},
          %{name: "tags", type: {:list, :string}, nullable?: true}
        ]
      ]
    }

    assert Metadata.to_file(metadata_file, metadata, root: root) == :ok

    written = File.read!(metadata_file)
    assert written =~ ~s("lib/accounts/sql/find_account.sql")
    assert written =~ "params:"
    assert written =~ ":integer"
    assert written =~ "{:list, :string}"
    assert written =~ "nullable?: true"

    assert Metadata.from_file(metadata_file, root: root) == {:ok, metadata}
  end

  test "to_file reports write failures" do
    root = Squirrelix.TestSupport.tmp_dir!("squirr_elix-metadata")
    # Parent path is a file, so mkdir_p / write must fail.
    blocker = Path.join(root, "not-a-directory")
    File.write!(blocker, "nope")
    metadata_file = Path.join(blocker, "squirr_elix.exs")

    assert {:error, %Squirrelix.Error.CannotWriteFile{file: ^metadata_file}} =
             Metadata.to_file(metadata_file, %{}, root: root)
  end
end
