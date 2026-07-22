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

defmodule Squirrelixir.Error.InvalidQueryMetadataFile do
  @moduledoc """
  Error returned when a query metadata file cannot be evaluated to a metadata map.
  """

  @enforce_keys [:file, :reason]
  defstruct [:file, :reason]

  @type t :: %__MODULE__{file: String.t(), reason: term()}
end

defmodule Squirrelixir.Error.UnsupportedPostgresType do
  @moduledoc """
  Error returned when a Postgres type has no Elixir mapping yet.
  """

  @enforce_keys [:name]
  defstruct [:name, :hint]

  @type t :: %__MODULE__{name: String.t(), hint: String.t() | nil}
end

defmodule Squirrelixir.Error.QueryHasInvalidEnum do
  @moduledoc """
  Error returned when a Postgres enum cannot be represented in generated Elixir code.
  """

  @enforce_keys [:file, :starting_line, :content, :enum_name, :reason]
  defstruct [:file, :starting_line, :content, :enum_name, :reason]

  @type reason ::
          :no_variants
          | {:invalid_name, String.t()}
          | {:invalid_variants, [String.t()]}

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          enum_name: String.t(),
          reason: reason()
        }
end

defmodule Squirrelixir.Error.PostgresSyntaxError do
  @moduledoc """
  Error returned when Postgres rejects query syntax during inference.
  """

  @enforce_keys [:file, :starting_line, :content, :message]
  defstruct [:file, :starting_line, :content, :message, :position]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          message: String.t(),
          position: pos_integer() | nil
        }
end

defmodule Squirrelixir.Error.MissingPostgresTable do
  @moduledoc """
  Error returned when query inference references a table Postgres cannot find.
  """

  @enforce_keys [:file, :starting_line, :content, :message]
  defstruct [:file, :starting_line, :content, :message, :table, :position]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          message: String.t(),
          table: String.t() | nil,
          position: pos_integer() | nil
        }
end

defmodule Squirrelixir.Error.MissingPostgresColumn do
  @moduledoc """
  Error returned when query inference references a column Postgres cannot find.
  """

  @enforce_keys [:file, :starting_line, :content, :message]
  defstruct [:file, :starting_line, :content, :message, :column, :position]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          message: String.t(),
          column: String.t() | nil,
          position: pos_integer() | nil
        }
end

defmodule Squirrelixir.Error.PostgresInferenceError do
  @moduledoc """
  Error returned when Postgres rejects query inference for an unclassified reason.
  """

  @enforce_keys [:file, :starting_line, :content, :message]
  defstruct [:file, :starting_line, :content, :message, :code, :position]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          message: String.t(),
          code: atom() | nil,
          position: pos_integer() | nil
        }
end
