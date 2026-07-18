defmodule Squirrelixir.Error.CannotReadFile do
  @enforce_keys [:file, :reason]
  defstruct [:file, :reason]

  @type t :: %__MODULE__{file: String.t(), reason: File.posix()}
end

defmodule Squirrelixir.Error.QueryFileHasInvalidName do
  @enforce_keys [:file, :reason]
  defstruct [:file, :reason, :suggested_name]

  @type reason :: :empty | {:invalid_grapheme, non_neg_integer(), String.t()}
  @type t :: %__MODULE__{file: String.t(), reason: reason(), suggested_name: String.t() | nil}
end
