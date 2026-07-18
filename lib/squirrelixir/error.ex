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

defmodule Squirrelixir.Error.CannotOverwriteFile do
  @enforce_keys [:file]
  defstruct [:file]

  @type t :: %__MODULE__{file: String.t()}
end

defmodule Squirrelixir.Error.CannotWriteFile do
  @enforce_keys [:file, :reason]
  defstruct [:file, :reason]

  @type t :: %__MODULE__{file: String.t(), reason: File.posix()}
end

defmodule Squirrelixir.Error.OutdatedFile do
  @enforce_keys [:file]
  defstruct [:file]

  @type t :: %__MODULE__{file: String.t()}
end

defmodule Squirrelixir.Error.DuplicateReturnColumns do
  @enforce_keys [:file, :starting_line, :content, :names]
  defstruct [:file, :starting_line, :content, :names]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          names: [String.t()]
        }
end
