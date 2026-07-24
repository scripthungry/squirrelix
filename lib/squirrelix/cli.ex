defmodule Squirrelix.CLI do
  @moduledoc """
  Project discovery and PostgreSQL connection helpers.

  This module mirrors upstream Squirrel CLI behaviour using Elixir data structures:
  maps for discovered files, structs for connection options, and `{:ok, _}` /
  `{:error, reason}` tuples for fallible operations.
  """

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

  @spec parse_connection_url(String.t()) ::
          {:ok, ConnectionOptions.t()} | {:error, :invalid_url}
  def parse_connection_url(raw) when is_binary(raw) do
    with %URI{} = uri <- URI.parse(raw),
         :ok <- check_scheme(uri.scheme),
         {:ok, timeout} <- parse_timeout(uri.query) do
      {user, password} = parse_user_and_password(uri.userinfo)
      database = parse_database(uri.path)

      {:ok,
       %ConnectionOptions{
         host: default_if_nil_or_empty(uri.host, @default_host),
         port: uri.port || @default_port,
         user: default_if_nil_or_empty(user, @default_user),
         password: default_if_nil_or_empty(password, @default_password),
         database: default_if_nil_or_empty(database, @default_database),
         timeout_seconds: timeout
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
        env_value(env, "PGCONNECT_TIMEOUT", nil) |> parse_int_or_default(@default_timeout)
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

  defp parse_timeout(nil), do: {:ok, @default_timeout}

  defp parse_timeout(query) do
    params = URI.decode_query(query)

    case Map.fetch(params, "connect_timeout") do
      :error ->
        {:ok, @default_timeout}

      {:ok, timeout} ->
        case Integer.parse(timeout) do
          {value, ""} -> {:ok, value}
          _ -> :error
        end
    end
  rescue
    _ -> :error
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
