defmodule Squirrelixir.Error.CannotReadFile do
  @moduledoc """
  Error returned when a file cannot be read.
  """

  @enforce_keys [:file, :reason]
  defstruct [:file, :reason]

  @type t :: %__MODULE__{file: String.t(), reason: File.posix()}
end

defmodule Squirrelixir.Error.QueryFileHasInvalidName do
  @moduledoc """
  Error returned when a SQL filename cannot become an Elixir function name.
  """

  @enforce_keys [:file, :reason]
  defstruct [:file, :reason, :suggested_name]

  @type reason :: :empty | {:invalid_grapheme, non_neg_integer(), String.t()}
  @type t :: %__MODULE__{file: String.t(), reason: reason(), suggested_name: String.t() | nil}
end

defmodule Squirrelixir.Error.CannotOverwriteFile do
  @moduledoc """
  Error returned when a generated file would overwrite human-written code.
  """

  @enforce_keys [:file]
  defstruct [:file]

  @type t :: %__MODULE__{file: String.t()}
end

defmodule Squirrelixir.Error.CannotWriteFile do
  @moduledoc """
  Error returned when generated content cannot be written.
  """

  @enforce_keys [:file, :reason]
  defstruct [:file, :reason]

  @type t :: %__MODULE__{file: String.t(), reason: File.posix()}
end

defmodule Squirrelixir.Error.OutdatedFile do
  @moduledoc """
  Error returned when an existing generated file differs from expected output.
  """

  @enforce_keys [:file]
  defstruct [:file]

  @type t :: %__MODULE__{file: String.t()}
end

defmodule Squirrelixir.Error.DuplicateReturnColumns do
  @moduledoc """
  Error returned when a query result contains duplicate column names.
  """

  @enforce_keys [:file, :starting_line, :content, :names]
  defstruct [:file, :starting_line, :content, :names]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          names: [String.t()]
        }
end

defmodule Squirrelixir.Error.MissingQueryMetadata do
  @moduledoc """
  Error returned when no parameter and return metadata is available for a query.
  """

  @enforce_keys [:file]
  defstruct [:file]

  @type t :: %__MODULE__{file: String.t()}
end

defmodule Squirrelixir.Error.MissingQueryMetadataField do
  @moduledoc """
  Error returned when query metadata is missing a required field.
  """

  @enforce_keys [:file, :field]
  defstruct [:file, :field]

  @type t :: %__MODULE__{file: String.t(), field: :params | :returns}
end
