defmodule Squirrelix.CLI do
  @moduledoc false

  alias Squirrelix.ConnectionOptions
  alias Squirrelix.Project
  alias Squirrelix.QueryDirectory

  @default_host "localhost"
  @default_user "postgres"
  @default_database "database"
  @default_password ""
  @default_port 5432
  @default_timeout 5

  @type discovered_sql_files :: %{Path.t() => [Path.t()]}

  @doc """
  Resolves connection options from environment and Mix/CLI opts.

  Precedence (highest first): flag overrides → `:url` → `DATABASE_URL` → `PG*` →
  defaults.
  """
  @spec resolve_connection_options(map(), keyword()) ::
          {:ok, ConnectionOptions.t()} | {:error, :invalid_url}
  def resolve_connection_options(env, opts \\ []) when is_map(env) and is_list(opts) do
    project_name = Keyword.get(opts, :project_name, "postgres")

    with {:ok, from_url} <- url_override(env, opts) do
      base =
        env
        |> connection_options_from_variables(project_name)
        |> merge_connection_options(from_url)
        |> merge_flag_overrides(opts)

      {:ok, base}
    end
  end

  @spec parse_connection_url(String.t()) ::
          {:ok, ConnectionOptions.t()} | {:error, :invalid_url}
  def parse_connection_url(raw) when is_binary(raw) do
    with %URI{} = uri <- URI.parse(raw),
         :ok <- check_scheme(uri.scheme),
         {:ok, timeout, ssl} <- parse_query_options(uri.query) do
      {user, password} = parse_user_and_password(uri.userinfo)
      database = parse_database(uri.path)

      {:ok,
       %ConnectionOptions{
         host: default_if_nil_or_empty(uri.host, @default_host),
         port: uri.port || @default_port,
         user: default_if_nil_or_empty(user, @default_user),
         password: default_if_nil_or_empty(password, @default_password),
         database: default_if_nil_or_empty(database, @default_database),
         timeout_seconds: timeout,
         ssl: ssl
       }}
    else
      _ -> {:error, :invalid_url}
    end
  end

  @spec connection_options_from_variables(map(), String.t() | nil) :: ConnectionOptions.t()
  def connection_options_from_variables(env, project_name) when is_map(env) do
    %ConnectionOptions{
      host: env_value(env, "PGHOST", @default_host),
      user: env_value(env, "PGUSER", @default_user),
      password: env_value(env, "PGPASSWORD", @default_password),
      database:
        env_value(env, "PGDATABASE", project_name)
        |> default_if_nil_or_empty(@default_database),
      port: env_value(env, "PGPORT", nil) |> parse_int_or_default(@default_port),
      timeout_seconds:
        env_value(env, "PGCONNECT_TIMEOUT", nil) |> parse_int_or_default(@default_timeout),
      ssl: ssl_from_env_mode(env_value(env, "PGSSLMODE", nil))
    }
  end

  @doc """
  Recursively finds `sql/` directories and their `.sql` files under `path`.

  Returns a map of directory paths to sorted SQL file paths.
  """
  @spec discover_sql_directories(Path.t()) :: discovered_sql_files()
  def discover_sql_directories(path) when is_binary(path) do
    do_discover_sql_directories(path)
  end

  @spec query_files(Path.t()) :: discovered_sql_files()
  def query_files(root) when is_binary(root) do
    root
    |> Project.source_roots()
    |> Enum.map(&discover_sql_directories/1)
    |> Enum.reduce(%{}, &Map.merge/2)
  end

  @spec query_directories(Path.t()) :: [QueryDirectory.t()]
  def query_directories(root) when is_binary(root) do
    root
    |> query_files()
    |> QueryDirectory.from_discovered_files()
  end

  @spec directory_to_output_file(String.t()) :: String.t()
  def directory_to_output_file(directory) when is_binary(directory) do
    directory
    |> Path.dirname()
    |> Path.join("sql.ex")
  end

  defp url_override(env, opts) do
    case Keyword.fetch(opts, :url) do
      {:ok, url} when is_binary(url) and url != "" ->
        parse_connection_url(url)

      _ ->
        case Map.get(env, "DATABASE_URL") do
          url when is_binary(url) and url != "" -> parse_connection_url(url)
          _ -> {:ok, nil}
        end
    end
  end

  defp merge_connection_options(%ConnectionOptions{} = base, nil), do: base

  defp merge_connection_options(%ConnectionOptions{} = base, %ConnectionOptions{} = override) do
    %ConnectionOptions{
      host: override.host || base.host,
      port: override.port || base.port,
      user: override.user || base.user,
      password: prefer_password(override.password, base.password),
      database: override.database || base.database,
      timeout_seconds: override.timeout_seconds || base.timeout_seconds,
      ssl: prefer_ssl(override.ssl, base.ssl)
    }
  end

  defp merge_flag_overrides(%ConnectionOptions{} = base, opts) do
    overrides =
      [
        host: Keyword.get(opts, :hostname),
        port: Keyword.get(opts, :port),
        user: Keyword.get(opts, :username),
        password: Keyword.get(opts, :password),
        database: Keyword.get(opts, :database)
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    struct!(base, overrides)
  end

  # Empty password from a URL like postgres://user@host/db should not wipe PGPASSWORD.
  defp prefer_password("", base), do: base
  defp prefer_password(password, _base), do: password

  defp prefer_ssl(nil, base), do: base
  defp prefer_ssl(ssl, _base), do: ssl

  defp do_discover_sql_directories(path) do
    if Path.basename(path) == "sql" do
      files =
        case File.ls(path) do
          {:ok, entries} ->
            entries
            |> Enum.map(&Path.join(path, &1))
            |> Enum.filter(&(File.regular?(&1) and Path.extname(&1) == ".sql"))
            |> Enum.sort()

          {:error, _reason} ->
            []
        end

      %{path => files}
    else
      path
      |> list_directories()
      |> Enum.map(&do_discover_sql_directories/1)
      |> Enum.reduce(%{}, &Map.merge/2)
    end
  end

  defp list_directories(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(path, &1))
        |> Enum.filter(&File.dir?/1)

      {:error, :enoent} ->
        []

      {:error, _reason} ->
        raise "couldn't read directory: #{path}"
    end
  end

  defp check_scheme(nil), do: :ok
  defp check_scheme("postgres"), do: :ok
  defp check_scheme("postgresql"), do: :ok
  defp check_scheme(_), do: :error

  defp parse_user_and_password(nil), do: {nil, nil}

  defp parse_user_and_password(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {user, nil}
      [user, password] -> {user, password}
      _ -> {nil, nil}
    end
  end

  defp parse_database(nil), do: nil

  defp parse_database(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      [database | _rest] -> database
      [] -> nil
    end
  end

  defp parse_query_options(nil), do: {:ok, @default_timeout, nil}

  defp parse_query_options(query) do
    params = URI.decode_query(query)

    with {:ok, timeout} <- parse_timeout_param(params),
         {:ok, ssl} <- parse_ssl_param(params) do
      {:ok, timeout, ssl}
    end
  rescue
    _ -> :error
  end

  defp parse_timeout_param(params) do
    case Map.fetch(params, "connect_timeout") do
      :error ->
        {:ok, @default_timeout}

      {:ok, timeout} ->
        case Integer.parse(timeout) do
          {value, ""} -> {:ok, value}
          _ -> :error
        end
    end
  end

  defp parse_ssl_param(params) do
    cond do
      Map.has_key?(params, "sslmode") ->
        case ssl_from_mode(Map.get(params, "sslmode")) do
          :error -> :error
          ssl -> {:ok, ssl}
        end

      Map.has_key?(params, "ssl") ->
        case Map.get(params, "ssl") do
          value when value in ["true", "1"] -> {:ok, ssl_from_mode("require")}
          value when value in ["false", "0"] -> {:ok, false}
          _ -> :error
        end

      true ->
        {:ok, nil}
    end
  end

  # Maps libpq sslmode values to Postgrex `:ssl` options.
  # `allow`/`prefer` cannot negotiate fallback in Postgrex; treat as off.
  # `require` encrypts without CA verification (common hosted-DB DATABASE_URL shape).
  # `verify-ca`/`verify-full` use Postgrex secure defaults (`ssl: true`).
  defp ssl_from_mode(nil), do: nil
  defp ssl_from_mode(""), do: nil
  defp ssl_from_mode("disable"), do: false
  defp ssl_from_mode("allow"), do: false
  defp ssl_from_mode("prefer"), do: false
  defp ssl_from_mode("require"), do: [verify: :verify_none]
  defp ssl_from_mode("verify-ca"), do: true
  defp ssl_from_mode("verify-full"), do: true
  defp ssl_from_mode(_), do: :error

  defp ssl_from_env_mode(mode) do
    case ssl_from_mode(mode) do
      :error -> false
      nil -> false
      ssl -> ssl
    end
  end

  defp env_value(env, key, default), do: Map.get(env, key, default)

  defp parse_int_or_default(nil, default), do: default

  defp parse_int_or_default(value, _default) when is_integer(value), do: value

  defp parse_int_or_default(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> int_value
      _ -> default
    end
  end

  defp parse_int_or_default(_value, default), do: default

  defp default_if_nil_or_empty(nil, default), do: default
  defp default_if_nil_or_empty("", default), do: default
  defp default_if_nil_or_empty(value, _default), do: value
end
