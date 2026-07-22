defmodule SquirrElix.MixTask do
  @moduledoc false

  alias SquirrElix.CLI
  alias SquirrElix.CodegenCheckSummary
  alias SquirrElix.CodegenSummary
  alias SquirrElix.ConnectionOptions
  alias SquirrElix.Metadata
  alias SquirrElix.Postgres

  @switches [
    metadata: :string,
    infer: :boolean,
    url: :string,
    database: :string,
    hostname: :string,
    username: :string,
    password: :string,
    port: :integer
  ]

  @spec generate([String.t()]) :: :ok
  def generate(args) do
    root = File.cwd!()
    opts = parse_args!(args)

    with_query_source!(opts, root, fn query_source ->
      root
      |> SquirrElix.generate(query_source, version: version())
      |> report_generate_summary()
    end)
  end

  @spec check([String.t()]) :: :ok
  def check(args) do
    root = File.cwd!()
    opts = parse_args!(args)

    with_query_source!(opts, root, fn query_source ->
      root
      |> SquirrElix.check(query_source, version: version())
      |> report_check_summary()
    end)
  end

  defp with_query_source!(opts, root, callback) do
    if opts[:infer] do
      with_postgres_inferrer!(opts, callback)
    else
      callback.(load_metadata!(opts, root))
    end
  end

  defp with_postgres_inferrer!(opts, callback) do
    case Postgrex.start_link(connection_opts(opts)) do
      {:ok, conn} ->
        try do
          callback.(Postgres.inferrer(conn))
        after
          GenServer.stop(conn)
        end

      {:error, error} ->
        Mix.raise("Could not connect to Postgres: #{inspect(error)}")
    end
  end

  defp connection_opts(opts) do
    opts
    |> base_connection_opts()
    |> Keyword.merge(env_connection_opts())
    |> Keyword.merge(flag_connection_opts(opts))
    |> Keyword.put_new_lazy(:database, fn -> System.get_env("PGDATABASE") || "postgres" end)
  end

  defp base_connection_opts(opts) do
    case Keyword.fetch(opts, :url) do
      {:ok, url} -> url_connection_opts!(url)
      :error -> []
    end
  end

  defp url_connection_opts!(url) do
    case CLI.parse_connection_url(url) do
      {:ok, connection_options} -> postgrex_connection_opts(connection_options)
      {:error, :invalid_url} -> Mix.raise("Invalid Postgres connection URL")
    end
  end

  defp postgrex_connection_opts(%ConnectionOptions{} = connection_options) do
    [
      hostname: connection_options.host,
      port: connection_options.port,
      username: connection_options.user,
      password: connection_options.password,
      database: connection_options.database,
      timeout: connection_options.timeout_seconds * 1000
    ]
  end

  defp env_connection_opts do
    [
      hostname: System.get_env("PGHOST"),
      username: System.get_env("PGUSER"),
      password: System.get_env("PGPASSWORD"),
      database: System.get_env("PGDATABASE"),
      port: parse_port(System.get_env("PGPORT"))
    ]
    |> compact_opts()
  end

  defp flag_connection_opts(opts) do
    opts
    |> Keyword.take([:database, :hostname, :username, :password, :port])
    |> compact_opts()
  end

  defp compact_opts(opts) do
    Enum.reject(opts, fn {_key, value} -> value in [nil, ""] end)
  end

  defp parse_port(nil), do: nil

  defp parse_port(port) when is_binary(port) do
    case Integer.parse(port) do
      {value, ""} -> value
      _invalid -> nil
    end
  end

  defp load_metadata!(opts, root) do
    metadata_file = opts |> Keyword.get(:metadata, "squirr_elix.exs") |> Path.expand(root)

    case Metadata.from_file(metadata_file, root: root) do
      {:ok, metadata} -> metadata
      {:error, error} -> Mix.raise("Could not load SquirrElix metadata: #{inspect(error)}")
    end
  end

  defp parse_args!(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [], []} -> opts
      {_opts, extra, []} -> Mix.raise("Unexpected arguments: #{Enum.join(extra, " ")}")
      {_opts, _extra, invalid} -> Mix.raise("Invalid options: #{inspect(invalid)}")
    end
  end

  defp report_generate_summary(%CodegenSummary{status: :ok, generated_count: count}) do
    Mix.shell().info("Generated #{count} #{pluralize(count, "query", "queries")}.")
    :ok
  end

  defp report_generate_summary(%CodegenSummary{status: :empty}) do
    Mix.shell().info("No SQL queries found.")
    :ok
  end

  defp report_generate_summary(%CodegenSummary{errors: errors}) do
    Mix.raise("SquirrElix generation failed: #{inspect(errors)}")
  end

  defp report_check_summary(%CodegenCheckSummary{status: :ok, checked_count: count}) do
    Mix.shell().info("All #{count} #{pluralize(count, "query", "queries")} current.")
    :ok
  end

  defp report_check_summary(%CodegenCheckSummary{status: :empty}) do
    Mix.shell().info("No SQL queries found.")
    :ok
  end

  defp report_check_summary(%CodegenCheckSummary{errors: errors}) do
    Mix.raise("SquirrElix check failed: #{inspect(errors)}")
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp version do
    Application.spec(:squirr_elix, :vsn)
    |> to_string()
  end
end
