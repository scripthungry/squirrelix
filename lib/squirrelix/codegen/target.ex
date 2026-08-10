defmodule Squirrelix.Codegen.Target do
  @moduledoc false

  # Emission context for a generated SQL module: runner calling convention and
  # reserved argument names. Name resolution must see `first_arg` so Ecto's
  # `repo` (and any future runner) cannot collide with a parameter name.

  alias Squirrelix.Codegen.Runtime

  @enforce_keys [:runner, :first_arg, :first_arg_type, :query_bang, :query_soft]
  defstruct [:runner, :first_arg, :first_arg_type, :query_bang, :query_soft]

  @type runner :: :postgrex | :ecto

  @type t :: %__MODULE__{
          runner: runner(),
          first_arg: String.t(),
          first_arg_type: String.t(),
          query_bang: (String.t(), String.t() -> String.t()),
          query_soft: (String.t(), String.t() -> String.t())
        }

  @spec reserved_argument_names(t()) :: MapSet.t(String.t())
  def reserved_argument_names(%__MODULE__{first_arg: first_arg})
      when is_binary(first_arg) do
    MapSet.put(Runtime.reserved_names(), first_arg)
  end
end
