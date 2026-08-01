# Postgrex logs expected unknown-OID reloads at debug during inference tests.
Logger.configure(level: :info)

ExUnit.start()

defmodule Squirrelix.TestSupport do
  @moduledoc false

  def tmp_dir!(prefix) when is_binary(prefix) do
    suffix =
      10
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    path = Path.join(System.tmp_dir!(), "#{prefix}-#{suffix}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  def compile_string(code) when is_binary(code) do
    module = module_from_code!(code)

    # Serialize per module name: async tests often generate the same MyApp.SQL
    # module and race on unload/compile ("currently being defined").
    case :global.trans({:squirr_elix_test_compile, module}, fn ->
           unload_module(module)
           Code.compile_string(code)
         end) do
      {:aborted, reason} ->
        raise "could not acquire compile lock for #{inspect(module)}: #{inspect(reason)}"

      compiled ->
        compiled
    end
  end

  def unload_module(module) when is_atom(module) do
    case :code.is_loaded(module) do
      false ->
        :ok

      {_module, _} ->
        :code.purge(module)
        :code.delete(module)
    end
  end

  defp module_from_code!(code) when is_binary(code) do
    case Regex.run(~r/defmodule\s+([A-Z][\w\.]+)\s+do/, code) do
      [_, mod] ->
        mod |> String.split(".") |> Module.concat()

      _ ->
        raise ArgumentError, "could not find defmodule in generated code"
    end
  end

  def tmp_mix_project(app) when is_atom(app) do
    path = tmp_dir!("squirr_elix-mix-project")

    File.write!(Path.join(path, "mix.exs"), """
    defmodule TempProject.MixProject do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0"]
      end
    end
    """)

    path
  end

  @doc """
  Postgrex options for live Postgres tests.

  Prefers standard `PG*` environment variables (as used in CI). Falls back to
  peer-auth style local defaults (`USER` / `postgres` database).
  """
  def postgres_opts(extra \\ []) when is_list(extra) do
    [
      hostname: System.get_env("PGHOST") || "localhost",
      port: parse_port(System.get_env("PGPORT")),
      username: System.get_env("PGUSER") || System.get_env("USER") || "postgres",
      password: System.get_env("PGPASSWORD"),
      database: System.get_env("PGDATABASE") || "postgres",
      log: false
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Keyword.merge(extra)
  end

  def postgres_url do
    opts = postgres_opts()
    user = Keyword.fetch!(opts, :username)
    host = Keyword.get(opts, :hostname, "localhost")
    port = Keyword.get(opts, :port, 5432)
    database = Keyword.fetch!(opts, :database)
    password = Keyword.get(opts, :password)

    auth =
      if password in [nil, ""] do
        user
      else
        "#{user}:#{password}"
      end

    "postgres://#{auth}@#{host}:#{port}/#{database}"
  end

  defp parse_port(nil), do: 5432

  defp parse_port(port) when is_binary(port) do
    case Integer.parse(port) do
      {value, ""} -> value
      _ -> 5432
    end
  end
end
