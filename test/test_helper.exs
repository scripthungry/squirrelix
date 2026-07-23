# Postgrex logs expected unknown-OID reloads at debug during inference tests.
Logger.configure(level: :info)

ExUnit.start()

defmodule SquirrElix.TestSupport do
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
    code
    |> module_from_code!()
    |> unload_module()

    Code.compile_string(code)
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
end
