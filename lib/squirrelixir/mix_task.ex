defmodule Squirrelixir.MixTask do
  @moduledoc false

  alias Squirrelixir.CodegenCheckSummary
  alias Squirrelixir.CodegenSummary
  alias Squirrelixir.Metadata

  @switches [metadata: :string]

  @spec generate([String.t()]) :: :ok
  def generate(args) do
    root = File.cwd!()
    metadata = load_metadata!(args, root)

    root
    |> Squirrelixir.generate(metadata, version: version())
    |> report_generate_summary()
  end

  @spec check([String.t()]) :: :ok
  def check(args) do
    root = File.cwd!()
    metadata = load_metadata!(args, root)

    root
    |> Squirrelixir.check(metadata, version: version())
    |> report_check_summary()
  end

  defp load_metadata!(args, root) do
    opts = parse_args!(args)
    metadata_file = opts |> Keyword.get(:metadata, "squirrelixir.exs") |> Path.expand(root)

    case Metadata.from_file(metadata_file, root: root) do
      {:ok, metadata} -> metadata
      {:error, error} -> Mix.raise("Could not load Squirrelixir metadata: #{inspect(error)}")
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
    Mix.raise("Squirrelixir generation failed: #{inspect(errors)}")
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
    Mix.raise("Squirrelixir check failed: #{inspect(errors)}")
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp version do
    Application.spec(:squirrelixir, :vsn)
    |> to_string()
  end
end
