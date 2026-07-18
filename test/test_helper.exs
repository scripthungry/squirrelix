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
end
