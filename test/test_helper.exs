ExUnit.start()

defmodule Squirrelixir.TestSupport do
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

  def tmp_mix_project(app) when is_atom(app) do
    path = tmp_dir!("squirrelixir-mix-project")

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
