defmodule Mix.Tasks.Squirrelixir.Check do
  @moduledoc """
  Checks generated Elixir query modules without writing files.
  """

  use Mix.Task

  @shortdoc "Checks Squirrelixir query modules"

  @impl Mix.Task
  def run(args) do
    Squirrelixir.MixTask.check(args)
  end
end
