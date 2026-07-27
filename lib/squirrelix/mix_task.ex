defmodule Squirrelix.MixTask do
  @moduledoc false

  alias Squirrelix.CLI
  alias Squirrelix.CodegenCheckSummary
  alias Squirrelix.CodegenSummary
  alias Squirrelix.Error
  alias Squirrelix.Inference
  alias Squirrelix.Metadata
  alias Squirrelix.Postgres
  alias Squirrelix.Watch

  @switches [
    metadata: :string,
    write_metadata: :string,
    infer: :boolean,
    watch: :boolean,
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

    if opts[:watch] do
      watch_generate!(root, opts)
    else
      generate_once!(root, opts)
    end
  end

  @spec check([String.t()]) :: :ok
  def check(args) do
    root = File.cwd!()
    opts = parse_args!(args)

    if opts[:watch] do
      Mix.raise("--watch is only supported by mix squirrelix.gen")
    end

    with_query_source!(opts, root, fn query_source ->
      root
      |> Squirrelix.check(query_source, version: version())
      |> report_check_summary()
    end)
  end

  defp watch_generate!(root, opts) do
    generate_once!(root, opts)

    dirs = Watch.watchable_dirs(root)

    Mix.shell().info(
      "Watching for .sql changes under {lib,test,dev}/**/sql/. Press Ctrl-C to stop."
    )

    debounce_ms = Application.get_env(:squirr_elix, :watch_debounce_ms, 200)

    after_start =
      case Application.get_env(:squirr_elix, :watch_test_hook) do
        fun when is_function(fun, 1) -> fun
        _ -> nil
      end

    Watch.watch!(
      root: root,
      dirs: dirs,
      debounce_ms: debounce_ms,
      after_start: after_start,
      on_change: fn -> soft_generate_once(root, opts) end
    )
  end

  defp generate_once!(root, opts) do
    with_query_source!(opts, root, fn query_source ->
      root
      |> Squirrelix.generate(query_source, version: version())
      |> report_generate_summary()
    end)
  end

  defp soft_generate_once(root, opts) do
    generate_once!(root, opts)
  rescue
    error in Mix.Error ->
      Mix.shell().error(Exception.message(error))
      :error
  end

  defp with_query_source!(opts, root, callback) do
    write_metadata? = is_binary(opts[:write_metadata])
    infer? = opts[:infer] == true

    cond do
      write_metadata? and not infer? ->
        Mix.raise("--write-metadata requires --infer")

      infer? and write_metadata? ->
        with_infer_and_optional_export!(opts, root, callback)

      infer? ->
        with_postgres_inferrer!(opts, callback)

      true ->
        callback.(load_metadata!(opts, root))
    end
  end

  defp with_infer_and_optional_export!(opts, root, callback) do
    with_postgres_inferrer!(opts, &maybe_export_then_callback(opts, root, &1, callback))
  end

  defp maybe_export_then_callback(opts, root, inferrer, callback) do
    case exportable_metadata(root, inferrer) do
      {:ok, metadata} ->
        write_metadata!(opts[:write_metadata], metadata, root)
        callback.(metadata)

      :has_errors ->
        callback.(inferrer)
    end
  end

  defp exportable_metadata(root, inferrer) do
    directories =
      root
      |> CLI.query_directories()
      |> Inference.from_query_directories(inferrer)

    if Enum.any?(directories, &(&1.errors != [])) do
      :has_errors
    else
      {:ok, Metadata.from_typed_directories(directories)}
    end
  end

  defp write_metadata!(path, metadata, root) do
    file = Path.expand(path, root)

    case Metadata.to_file(file, metadata, root: root) do
      :ok ->
        display = Path.relative_to(file, root)
        Mix.shell().info("Wrote metadata to #{display}.")
        :ok

      {:error, error} ->
        Mix.raise("Could not write Squirrelix metadata:\n\n#{Error.format(error)}")
    end
  end

  defp with_postgres_inferrer!(opts, callback) do
    {:ok, _} = Application.ensure_all_started(:postgrex)
    connection_options = build_connection_options(opts)

    case Postgres.connect(connection_options) do
      {:ok, conn} ->
        try do
          callback.(Postgres.inferrer(conn))
        after
          GenServer.stop(conn)
        end

      {:error, error} ->
        Mix.raise("Squirrelix connection failed:\n\n#{Error.format(error)}")
    end
  end

  # Precedence (highest first): flags → --url → DATABASE_URL → PG* → defaults.
  defp build_connection_options(opts) do
    case CLI.resolve_connection_options(System.get_env(), opts) do
      {:ok, connection_options} -> connection_options
      {:error, :invalid_url} -> Mix.raise("Invalid Postgres connection URL")
    end
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
