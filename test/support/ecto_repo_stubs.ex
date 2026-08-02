defmodule Squirrelix.TestSupport.RepoWithConfig do
  @moduledoc false

  def config do
    [
      hostname: "repo-host",
      username: "repo-user",
      password: "repo-pass",
      database: "repo_db",
      port: 5555,
      ssl: false,
      timeout: 9_000
    ]
  end
end

defmodule Squirrelix.TestSupport.RepoWithUrl do
  @moduledoc false

  def config do
    [
      hostname: "ignored-host",
      username: "ignored-user",
      password: "ignored-pass",
      database: "ignored_db",
      url: "postgres://url_user:url_pass@url-host:6543/url_db?connect_timeout=4"
    ]
  end
end

defmodule Squirrelix.TestSupport.RepoWithoutConfig do
  @moduledoc false
end
