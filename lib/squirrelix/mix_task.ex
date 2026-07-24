defmodule Squirrelix.MixTask do
  @moduledoc false

  alias Squirrelix.CLI
  alias Squirrelix.CodegenCheckSummary
  alias Squirrelix.CodegenSummary
  alias Squirrelix.ConnectionOptions
  alias Squirrelix.Error
  alias Squirrelix.Metadata
  alias Squirrelix.Postgres

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
      |> Squirrelix.generate(query_source, version: version())
      |> report_generate_summary()
    end)
  end

  @spec check([String.t()]) :: :ok
  def check(args) do
    root = File.cwd!()
    opts = parse_args!(args)

    with_query_source!(opts, root, fn query_source ->
      root
      |> Squirrelix.check(query_source, version: version())
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
    {:ok, _} = Application.ensure_all_started(:postgrex)

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

  # Precedence (highest first): CLI flags → URL → environment → defaults.
  defp connection_opts(opts) do
    System.get_env()
    |> CLI.connection_options_from_variables("postgres")
    |> maybe_merge_url(opts)
    |> merge_flag_overrides(opts)
    |> postgrex_connection_opts()
  end

  defp maybe_merge_url(%ConnectionOptions{} = base, opts) do
    case Keyword.fetch(opts, :url) do
      {:ok, url} ->
        case CLI.parse_connection_url(url) do
          {:ok, from_url} -> merge_connection_options(base, from_url)
          {:error, :invalid_url} -> Mix.raise("Invalid Postgres connection URL")
        end

      :error ->
        base
    end
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

  defp merge_connection_options(%ConnectionOptions{} = base, %ConnectionOptions{} = override) do
    %ConnectionOptions{
      host: override.host || base.host,
      port: override.port || base.port,
      user: override.user || base.user,
      password: prefer_password(override.password, base.password),
      database: override.database || base.database,
      timeout_seconds: override.timeout_seconds || base.timeout_seconds
    }
  end

  # Empty password from a URL like postgres://user@host/db should not wipe PGPASSWORD.
  defp prefer_password("", base), do: base
  defp prefer_password(password, _base), do: password

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

  defp load_metadata!(opts, root) do
    metadata_file = opts |> Keyword.get(:metadata, "squirr_elix.exs") |> Path.expand(root)

    case Metadata.from_file(metadata_file, root: root) do
      {:ok, metadata} ->
        metadata

      {:error, error} ->
        Mix.raise("Could not load Squirrelix metadata:\n\n#{Error.format(error)}")
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
    Mix.raise("Squirrelix generation failed:\n\n#{format_codegen_errors(errors)}")
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
    Mix.raise("Squirrelix check failed:\n\n#{format_codegen_errors(errors)}")
  end

  defp format_codegen_errors(errors) do
    Enum.map_join(errors, "\n\n", fn {directory, error} ->
      "#{directory}\n#{format_directory_error(error)}"
    end)
  end

  defp format_directory_error(errors) when is_list(errors), do: Error.format_all(errors)
  defp format_directory_error(%_{} = error), do: Error.format(error)
  defp format_directory_error(other), do: inspect(other)

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp version do
    Application.spec(:squirr_elix, :vsn)
    |> to_string()
  end
end
