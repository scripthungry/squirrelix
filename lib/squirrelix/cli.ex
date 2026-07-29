defmodule Squirrelix.CLI do
  @moduledoc false

  alias Squirrelix.ConnectionOptions
  alias Squirrelix.Error.CannotReadFile
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
        |> apply_connection_defaults()

      {:ok, base}
    end
  end

  @spec parse_connection_url(String.t()) ::
          {:ok, ConnectionOptions.t()} | {:error, :invalid_url}
  def parse_connection_url(raw) when is_binary(raw) do
    with {:ok, options} <- do_parse_connection_url(raw) do
      {:ok, apply_connection_defaults(options)}
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

  Returns `{:ok, map}` of directory paths to sorted SQL file paths, or
  `{:error, %CannotReadFile{}}` when a directory cannot be listed.
  """
  @spec discover_sql_directories(Path.t()) ::
          {:ok, discovered_sql_files()} | {:error, CannotReadFile.t()}
  def discover_sql_directories(path) when is_binary(path) do
    do_discover_sql_directories(path)
  end

  @spec query_files(Path.t()) :: {:ok, discovered_sql_files()} | {:error, CannotReadFile.t()}
  def query_files(root) when is_binary(root) do
    root
    |> Project.source_roots()
    |> Enum.reduce_while({:ok, %{}}, fn source_root, {:ok, acc} ->
      case discover_sql_directories(source_root) do
        {:ok, found} -> {:cont, {:ok, Map.merge(acc, found)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @spec query_directories(Path.t()) ::
          {:ok, [QueryDirectory.t()]} | {:error, CannotReadFile.t()}
  def query_directories(root) when is_binary(root) do
    case query_files(root) do
      {:ok, files} -> {:ok, QueryDirectory.from_discovered_files(files)}
      {:error, _} = error -> error
    end
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
        do_parse_connection_url(url)

      _ ->
        case Map.get(env, "DATABASE_URL") do
          url when is_binary(url) and url != "" -> do_parse_connection_url(url)
          _ -> {:ok, nil}
        end
    end
  end

  # Parse without filling library defaults so merge can keep present PG* values
  # for fields the URL omits.
  defp do_parse_connection_url(raw) when is_binary(raw) do
    with %URI{} = uri <- URI.parse(raw),
         :ok <- check_scheme(uri.scheme),
         {:ok, timeout, ssl} <- parse_query_options(uri.query) do
      {user, password} = parse_user_and_password(uri.userinfo)
      database = parse_database(uri.path)

      {:ok,
       %ConnectionOptions{
         host: blank_to_nil(uri.host),
         port: uri.port,
         user: blank_to_nil(user),
         password: password_from_url(password),
         database: blank_to_nil(database),
         timeout_seconds: timeout,
         ssl: ssl
       }}
    else
      _ -> {:error, :invalid_url}
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

  defp apply_connection_defaults(%ConnectionOptions{} = options) do
    %ConnectionOptions{
      host: default_if_nil_or_empty(options.host, @default_host),
      port: options.port || @default_port,
      user: default_if_nil_or_empty(options.user, @default_user),
      password: default_if_nil_or_empty(options.password, @default_password),
      database: default_if_nil_or_empty(options.database, @default_database),
      timeout_seconds: options.timeout_seconds || @default_timeout,
      ssl: options.ssl
    }
  end

  # Empty password from a URL like postgres://user@host/db should not wipe PGPASSWORD.
  # `nil` means the URL omitted a password; `""` means it was present but empty.
  defp prefer_password(nil, base), do: base
  defp prefer_password("", base), do: base
  defp prefer_password(password, _base), do: password

  defp prefer_ssl(nil, base), do: base
  defp prefer_ssl(ssl, _base), do: ssl

  defp do_discover_sql_directories(path) do
    case Path.basename(path) do
      "sql" -> list_sql_files(path)
      _ -> discover_nested_sql_directories(path)
    end
  end

  defp list_sql_files(path) do
    case File.ls(path) do
      {:ok, entries} ->
        files =
          entries
          |> Enum.map(&Path.join(path, &1))
          |> Enum.filter(&(File.regular?(&1) and Path.extname(&1) == ".sql"))
          |> Enum.sort()

        {:ok, %{path => files}}

      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, %CannotReadFile{file: path, reason: reason}}
    end
  end

  defp discover_nested_sql_directories(path) do
    with {:ok, directories} <- list_directories(path) do
      merge_discovered_directories(directories)
    end
  end

  defp merge_discovered_directories(directories) do
    Enum.reduce_while(directories, {:ok, %{}}, fn directory, {:ok, acc} ->
      case do_discover_sql_directories(directory) do
        {:ok, found} -> {:cont, {:ok, Map.merge(acc, found)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp list_directories(path) do
    case File.ls(path) do
      {:ok, entries} ->
        directories =
          entries
          |> Enum.map(&Path.join(path, &1))
          |> Enum.filter(&File.dir?/1)

        {:ok, directories}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, %CannotReadFile{file: path, reason: reason}}
    end
  end

  defp check_scheme(nil), do: :error
  defp check_scheme("postgres"), do: :ok
  defp check_scheme("postgresql"), do: :ok
  defp check_scheme(_), do: :error

  defp parse_user_and_password(nil), do: {nil, nil}

  defp parse_user_and_password(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {percent_decode(user), nil}
      [user, password] -> {percent_decode(user), percent_decode(password)}
      _ -> {nil, nil}
    end
  end

  defp percent_decode(value) when is_binary(value) do
    URI.decode(value)
  rescue
    ArgumentError -> value
  end

  defp password_from_url(nil), do: nil
  defp password_from_url(password), do: password

  defp parse_database(nil), do: nil

  defp parse_database(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      [database | _rest] -> percent_decode(database)
      [] -> nil
    end
  end

  # Missing query string → leave timeout unset so PGCONNECT_TIMEOUT can win on merge.
  defp parse_query_options(nil), do: {:ok, nil, nil}

  defp parse_query_options(query) do
    params = URI.decode_query(query)

    with {:ok, timeout} <- parse_timeout_param(params),
         {:ok, ssl} <- parse_ssl_param(params) do
      {:ok, timeout, ssl}
    end
  rescue
    ArgumentError -> :error
  end

  defp parse_timeout_param(params) do
    case Map.fetch(params, "connect_timeout") do
      :error ->
        {:ok, nil}

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

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp default_if_nil_or_empty(nil, default), do: default
  defp default_if_nil_or_empty("", default), do: default
  defp default_if_nil_or_empty(value, _default), do: value
end
