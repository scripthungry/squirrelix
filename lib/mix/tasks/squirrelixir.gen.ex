defmodule Mix.Tasks.Squirrelixir.Gen do
  @moduledoc """
  Generates Elixir query modules from SQL files discovered in the current project.
  """

  use Mix.Task

  @shortdoc "Generates Squirrelixir query modules"

  @impl Mix.Task
  def run(args) do
    Squirrelixir.MixTask.generate(args)
  end
end
