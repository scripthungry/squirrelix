defmodule SquirrelixRepoConfigTest do
  use ExUnit.Case, async: true

  alias Squirrelix.CLI
  alias Squirrelix.ConnectionOptions
  alias Squirrelix.RepoConfig
  alias Squirrelix.TestSupport.RepoWithConfig
  alias Squirrelix.TestSupport.RepoWithoutConfig
  alias Squirrelix.TestSupport.RepoWithUrl

  describe "RepoConfig.connection_options/1" do
    test "maps Ecto-style config/0 onto ConnectionOptions" do
      assert {:ok,
              %ConnectionOptions{
                host: "repo-host",
                user: "repo-user",
                password: "repo-pass",
                database: "repo_db",
                port: 5555,
                timeout_seconds: 9,
                ssl: false
              }} = RepoConfig.connection_options(RepoWithConfig)
    end

    test "accepts module name strings" do
      assert {:ok, %ConnectionOptions{host: "repo-host"}} =
               RepoConfig.connection_options("Squirrelix.TestSupport.RepoWithConfig")
    end

    test "prefers :url inside Repo config over discrete keys" do
      assert {:ok,
              %ConnectionOptions{
                host: "url-host",
                user: "url_user",
                password: "url_pass",
                database: "url_db",
                port: 6543,
                timeout_seconds: 4
              }} = RepoConfig.connection_options(RepoWithUrl)
    end

    test "rejects unknown or unloaded modules" do
      assert {:error, :invalid_repo} =
               RepoConfig.connection_options("NotAReal.RepoModule")
    end

    test "rejects modules without config/0" do
      assert {:error, :repo_config_unavailable} =
               RepoConfig.connection_options(RepoWithoutConfig)
    end

    test "rejects invalid module name strings" do
      assert {:error, :invalid_repo} = RepoConfig.connection_options("not a module")
      assert {:error, :invalid_repo} = RepoConfig.connection_options("")
    end
  end

  describe "CLI.resolve_connection_options/2 with :repo" do
    test "uses repo config below DATABASE_URL and above PG*" do
      env = %{
        "PGHOST" => "pghost",
        "PGUSER" => "pguser",
        "PGPASSWORD" => "pgpass",
        "PGDATABASE" => "pgdb",
        "PGPORT" => "5432"
      }

      assert {:ok,
              %ConnectionOptions{
                host: "repo-host",
                user: "repo-user",
                database: "repo_db",
                port: 5555
              }} =
               CLI.resolve_connection_options(env, repo: RepoWithConfig)
    end

    test "DATABASE_URL still beats repo config" do
      env = %{
        "DATABASE_URL" => "postgres://url_user:url_pass@urlhost:6543/url_db"
      }

      assert {:ok,
              %ConnectionOptions{
                host: "urlhost",
                user: "url_user",
                database: "url_db",
                port: 6543
              }} =
               CLI.resolve_connection_options(env, repo: RepoWithConfig)
    end

    test "flag overrides beat repo config" do
      assert {:ok, %ConnectionOptions{host: "flag-host", database: "repo_db"}} =
               CLI.resolve_connection_options(%{},
                 repo: RepoWithConfig,
                 hostname: "flag-host"
               )
    end
  end
end
