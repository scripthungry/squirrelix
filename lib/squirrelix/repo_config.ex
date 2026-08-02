defmodule Squirrelix.RepoConfig do
  @moduledoc false

  # Resolve Postgres connection options from an Ecto-like Repo module or config
  # keyword list. SquirrElix does not depend on Ecto; it only calls `config/0`
  # when exported and maps common Ecto SQL keys onto `ConnectionOptions`.

  alias Squirrelix.CLI
  alias Squirrelix.ConnectionOptions

  @type repo_ref :: module() | String.t()

  @spec connection_options(repo_ref()) ::
          {:ok, ConnectionOptions.t()}
          | {:error, :invalid_repo | :invalid_url | :repo_config_unavailable}
  def connection_options(repo) when is_atom(repo) do
    with :ok <- ensure_repo_loaded(repo),
         {:ok, config} <- fetch_repo_config(repo) do
      from_config(config)
    end
  end

  def connection_options(repo) when is_binary(repo) do
    case module_from_name(repo) do
      {:ok, module} -> connection_options(module)
      {:error, _} = error -> error
    end
  end

  @spec from_config(keyword()) ::
          {:ok, ConnectionOptions.t()} | {:error, :invalid_url}
  def from_config(config) when is_list(config) do
    with {:ok, from_url} <- url_from_config(config) do
      base = %ConnectionOptions{
        host: config_string(config, [:hostname, :host]),
        port: config_port(config),
        user: config_string(config, [:username, :user]),
        password: config_password(config),
        database: config_string(config, [:database]),
        timeout_seconds: config_timeout_seconds(config),
        ssl: config_ssl(config)
      }

      {:ok, merge_url(base, from_url)}
    end
  end

  defp module_from_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    if trimmed == "" or
         not Regex.match?(~r/^([A-Z][A-Za-z0-9_]*)(\.[A-Z][A-Za-z0-9_]*)*$/, trimmed) do
      {:error, :invalid_repo}
    else
      {:ok, Module.concat(String.split(trimmed, "."))}
    end
  end

  defp ensure_repo_loaded(repo) when is_atom(repo) do
    case Code.ensure_loaded(repo) do
      {:module, ^repo} -> :ok
      {:error, _} -> {:error, :invalid_repo}
    end
  end

  defp fetch_repo_config(repo) when is_atom(repo) do
    if function_exported?(repo, :config, 0) do
      case repo.config() do
        config when is_list(config) -> {:ok, config}
        _ -> {:error, :repo_config_unavailable}
      end
    else
      {:error, :repo_config_unavailable}
    end
  end

  defp url_from_config(config) do
    case first_present(config, [:url, :database_url]) do
      url when is_binary(url) and url != "" -> CLI.parse_connection_url(url)
      _ -> {:ok, nil}
    end
  end

  defp merge_url(base, nil), do: base

  defp merge_url(%ConnectionOptions{} = base, %ConnectionOptions{} = from_url) do
    %ConnectionOptions{
      host: from_url.host || base.host,
      port: from_url.port || base.port,
      user: from_url.user || base.user,
      password: prefer_password(from_url.password, base.password),
      database: from_url.database || base.database,
      timeout_seconds: from_url.timeout_seconds || base.timeout_seconds,
      ssl: prefer_ssl(from_url.ssl, base.ssl)
    }
  end

  defp prefer_password(nil, base), do: base
  defp prefer_password("", base), do: base
  defp prefer_password(password, _base), do: password

  defp prefer_ssl(nil, base), do: base
  defp prefer_ssl(ssl, _base), do: ssl

  defp config_string(config, keys) do
    case first_present(config, keys) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp config_password(config) do
    case Keyword.get(config, :password) do
      password when is_binary(password) -> password
      _ -> nil
    end
  end

  defp config_port(config) do
    case Keyword.get(config, :port) do
      port when is_integer(port) and port > 0 ->
        port

      port when is_binary(port) ->
        case Integer.parse(port) do
          {value, ""} when value > 0 -> value
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp config_timeout_seconds(config) do
    case first_present(config, [:timeout, :connect_timeout]) do
      timeout when is_integer(timeout) and timeout >= 0 ->
        # Ecto timeouts are milliseconds; ConnectionOptions uses seconds.
        div(timeout, 1000)

      _ ->
        nil
    end
  end

  defp config_ssl(config) do
    case Keyword.fetch(config, :ssl) do
      :error -> nil
      {:ok, ssl} -> ssl
    end
  end

  defp first_present(config, keys) do
    Enum.find_value(keys, fn key ->
      case Keyword.fetch(config, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end
end
