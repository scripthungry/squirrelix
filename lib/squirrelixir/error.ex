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

defmodule Squirrelixir.Error.QueryHasInvalidColumn do
  @moduledoc """
  Error returned when a query result column name cannot become an Elixir identifier.
  """

  @enforce_keys [:file, :starting_line, :content, :column_name, :reason]
  defstruct [:file, :starting_line, :content, :column_name, :reason, :suggested_name]

  @type reason :: :empty | {:invalid_grapheme, non_neg_integer(), String.t()}
  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          column_name: String.t(),
          reason: reason(),
          suggested_name: String.t() | nil
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
  Error returned when a Postgres enum has no variants.
  """

  @enforce_keys [:file, :starting_line, :content, :enum_name, :reason]
  defstruct [:file, :starting_line, :content, :enum_name, :reason]

  @type reason :: :no_variants

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

defmodule Squirrelixir.Error.MissingPostgresConstraint do
  @moduledoc """
  Error returned when query inference references a constraint Postgres cannot find.
  """

  @enforce_keys [:file, :starting_line, :content, :message]
  defstruct [:file, :starting_line, :content, :message, :constraint, :table, :position]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t(),
          message: String.t(),
          constraint: String.t() | nil,
          table: String.t() | nil,
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

defmodule Squirrelixir.Error do
  @moduledoc """
  Formatting and normalization helpers for Squirrelixir errors.
  """

  alias Squirrelixir.Error.CannotOverwriteFile
  alias Squirrelixir.Error.DuplicateReturnColumns
  alias Squirrelixir.Error.MissingPostgresColumn
  alias Squirrelixir.Error.MissingPostgresConstraint
  alias Squirrelixir.Error.MissingPostgresTable
  alias Squirrelixir.Error.OutdatedFile
  alias Squirrelixir.Error.PostgresInferenceError
  alias Squirrelixir.Error.PostgresSyntaxError
  alias Squirrelixir.Error.QueryFileHasInvalidName
  alias Squirrelixir.Error.QueryHasInvalidColumn
  alias Squirrelixir.Error.QueryHasInvalidEnum
  alias Squirrelixir.Error.UnsupportedPostgresType
  alias Squirrelixir.Query

  @spec normalize(struct()) :: struct()
  def normalize(%PostgresInferenceError{code: :undefined_object, message: message} = error)
      when is_binary(message) do
    if constraint_error_message?(message) do
      %MissingPostgresConstraint{
        file: error.file,
        starting_line: error.starting_line,
        content: error.content,
        message: message,
        constraint: constraint_name(message),
        table: constraint_table(message),
        position: error.position
      }
    else
      error
    end
  end

  def normalize(error), do: error

  @spec attach_query(struct(), Query.t()) :: struct()
  def attach_query(%{__struct__: module} = error, %Query{} = query) do
    if query_context_fields?(module) do
      %{error | file: query.file, starting_line: query.starting_line, content: query.content}
    else
      error
    end
  end

  @spec format(struct()) :: String.t()
  def format(error), do: error |> normalize() |> do_format()

  @spec format_all([struct()]) :: String.t()
  def format_all(errors) when is_list(errors) do
    Enum.map_join(errors, "\n\n", &format/1)
  end

  @spec postgresql_code(struct()) :: String.t() | nil
  def postgresql_code(%PostgresSyntaxError{}), do: "42601"
  def postgresql_code(%MissingPostgresTable{}), do: "42P01"
  def postgresql_code(%MissingPostgresColumn{}), do: "42703"
  def postgresql_code(%MissingPostgresConstraint{}), do: "42704"

  def postgresql_code(%PostgresInferenceError{code: code}) when is_atom(code) do
    Map.get(
      %{
        syntax_error: "42601",
        undefined_table: "42P01",
        undefined_column: "42703",
        undefined_object: "42704",
        feature_not_supported: "0A000"
      },
      code,
      code |> Atom.to_string() |> String.upcase()
    )
  end

  def postgresql_code(_error), do: nil

  defp query_context_fields?(module) do
    module
    |> Module.split()
    |> List.last()
    |> then(fn name ->
      name in [
        "PostgresSyntaxError",
        "MissingPostgresTable",
        "MissingPostgresColumn",
        "MissingPostgresConstraint",
        "PostgresInferenceError",
        "DuplicateReturnColumns",
        "QueryHasInvalidEnum",
        "QueryHasInvalidColumn"
      ]
    end)
  end

  defp do_format(%QueryFileHasInvalidName{} = error), do: format_query_file_name_error(error)

  defp do_format(%DuplicateReturnColumns{} = error),
    do: format_duplicate_return_columns_error(error)

  defp do_format(%QueryHasInvalidColumn{} = error), do: format_invalid_column_error(error)
  defp do_format(%QueryHasInvalidEnum{} = error), do: format_invalid_enum_error(error)
  defp do_format(%UnsupportedPostgresType{} = error), do: format_unsupported_type_error(error)
  defp do_format(%OutdatedFile{} = error), do: format_outdated_file_error(error)
  defp do_format(%CannotOverwriteFile{} = error), do: format_cannot_overwrite_file_error(error)

  defp do_format(error) do
    if postgres_query_error?(error) do
      format_postgres_query_error(error)
    else
      "Error: #{inspect(error)}"
    end
  end

  defp postgres_query_error?(%PostgresSyntaxError{}), do: true
  defp postgres_query_error?(%MissingPostgresTable{}), do: true
  defp postgres_query_error?(%MissingPostgresColumn{}), do: true
  defp postgres_query_error?(%MissingPostgresConstraint{}), do: true
  defp postgres_query_error?(%PostgresInferenceError{}), do: true
  defp postgres_query_error?(_error), do: false

  defp format_postgres_query_error(error) do
    title =
      case postgresql_code(error) do
        nil -> "Invalid query"
        code -> "Invalid query [#{code}]"
      end

    [
      "Error: #{title}",
      "",
      code_block(error),
      additional_message(error)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp format_query_file_name_error(%QueryFileHasInvalidName{} = error) do
    lines = [
      "Error: Query file with invalid name",
      "",
      "File #{error.file} doesn't have a valid name.",
      "The name of a file is used to generate a corresponding Elixir function, so it should be a valid Elixir identifier.",
      identifier_reason_message(error.reason),
      "Hint: A file name must start with a lowercase letter and can only contain lowercase letters, numbers and underscores."
    ]

    lines =
      case error.suggested_name do
        nil -> lines
        suggested_name -> lines ++ ["Maybe try renaming it to `#{suggested_name}`?"]
      end

    Enum.join(lines, "\n")
  end

  defp format_duplicate_return_columns_error(%DuplicateReturnColumns{} = error) do
    pretty_names = Enum.map_join(error.names, ", ", &"`#{&1}`")
    label = if length(error.names) == 1, do: "name", else: "names"

    [
      "Error: Duplicate names",
      "",
      code_block(error),
      "This query returns multiple values sharing the same #{label}: #{pretty_names}."
    ]
    |> Enum.join("\n")
  end

  defp format_invalid_column_error(%QueryHasInvalidColumn{reason: :empty} = error) do
    [
      "Error: Column with empty name",
      "",
      code_block(error),
      "A column returned by this query has the empty string as a name, all columns should have a valid Elixir identifier as name."
    ]
    |> Enum.join("\n")
  end

  defp format_invalid_column_error(%QueryHasInvalidColumn{} = error) do
    message =
      case error.suggested_name do
        nil -> "This is not a valid Elixir identifier"
        suggested_name -> "This is not a valid Elixir identifier, maybe try `#{suggested_name}`?"
      end

    [
      "Error: Column with invalid name",
      "",
      code_block(error, {error.column_name, message}),
      "Hint: A column name must start with a lowercase letter and can only contain lowercase letters, numbers and underscores."
    ]
    |> Enum.join("\n")
  end

  defp format_invalid_enum_error(%QueryHasInvalidEnum{} = error) do
    reason_message =
      case error.reason do
        :no_variants -> "it has no variants."
      end

    [
      "Error: Query with invalid enum",
      "",
      code_block(error),
      "One of the values in this query is the `#{error.enum_name}` enum, but it cannot be turned into a generated type because #{reason_message}"
    ]
    |> Enum.join("\n")
  end

  defp format_unsupported_type_error(%UnsupportedPostgresType{} = error) do
    lines = [
      "Error: Unsupported type",
      "",
      "One of the rows returned by this query has type `#{error.name}` which cannot currently generate code for."
    ]

    lines =
      case error.hint do
        nil -> lines
        hint -> lines ++ ["Hint: #{hint}"]
      end

    Enum.join(lines, "\n")
  end

  defp format_outdated_file_error(%OutdatedFile{} = error) do
    [
      "Error: Outdated file",
      "",
      "It looks like #{error.file} is outdated, try running `mix squirrelixir.gen` to generate a new up to date version."
    ]
    |> Enum.join("\n")
  end

  defp format_cannot_overwrite_file_error(%CannotOverwriteFile{} = error) do
    [
      "Error: Cannot overwrite file",
      "",
      "It looks like #{error.file} already exists and was not generated by Squirrelixir, it cannot be overwritten!",
      "Hint: Rename the file and run `mix squirrelixir.gen` again."
    ]
    |> Enum.join("\n")
  end

  defp code_block(
         %{file: file, content: content, starting_line: starting_line} = error,
         pointer \\ nil
       ) do
    pointer =
      case pointer do
        {column_name, message} -> pointer_for({column_name, message}, content)
        nil -> pointer_for(error)
        other -> other
      end

    lines = String.split(content, "\n")
    width = byte_size(Integer.to_string(starting_line + length(lines) - 1)) + 2
    padding = String.duplicate(" ", width + 1)

    header = [
      padding <> "╭─ #{file}",
      padding <> "│"
    ]

    body =
      lines
      |> Enum.with_index(starting_line)
      |> Enum.flat_map(fn {line, line_number} ->
        prefix = String.pad_leading("#{line_number} │ ", width)

        if pointer != nil and elem(pointer, 0) == line_number do
          {from, message} = elem(pointer, 1)
          caret = String.duplicate(" ", from) <> "┬"
          underline = String.duplicate(" ", from) <> "╰─ " <> message

          [
            prefix <> line,
            prefix <> caret,
            prefix <> underline
          ]
        else
          [prefix <> line]
        end
      end)

    footer = [padding <> "┆"]

    Enum.join(header ++ body ++ footer, "\n")
  end

  defp additional_message(%PostgresInferenceError{message: message}), do: message

  defp additional_message(%MissingPostgresConstraint{message: message, position: nil}),
    do: message

  defp additional_message(%{message: message, position: nil}), do: message
  defp additional_message(_error), do: ""

  defp pointer_for({column_name, message}, content)
       when is_binary(column_name) and is_binary(message) and is_binary(content) do
    case find_name_span(column_name, content) do
      {line_number, column} -> {line_number, {column, message}}
      :error -> nil
    end
  end

  defp pointer_for(%{position: position, message: message, content: content})
       when is_integer(position) and is_binary(message) and is_binary(content) do
    {line_number, column} = position_to_line_column(content, position)
    {line_number, {column, message}}
  end

  defp pointer_for(_error), do: nil

  defp find_name_span(name, content) do
    case :binary.match(content, name) do
      {offset, _length} ->
        offset_to_line_column(content, offset)

      :nomatch ->
        :error
    end
  end

  defp offset_to_line_column(content, offset) do
    prefix = binary_part(content, 0, offset)

    line_number =
      prefix
      |> String.graphemes()
      |> Enum.count(&(&1 == "\n"))
      |> Kernel.+(1)

    column =
      prefix
      |> String.split("\n")
      |> List.last()
      |> then(&String.length(&1 || ""))

    {line_number, column}
  end

  defp identifier_reason_message(:empty), do: "Reason: the file name is empty"

  defp identifier_reason_message({:invalid_grapheme, 0, grapheme}),
    do: "Reason: cannot start with #{inspect(grapheme)}"

  defp identifier_reason_message({:invalid_grapheme, position, grapheme}),
    do: "Reason: invalid character #{inspect(grapheme)} at position #{position}"

  defp position_to_line_column(content, position) do
    prefix = String.slice(content, 0, position - 1)

    line_number =
      prefix
      |> String.graphemes()
      |> Enum.count(&(&1 == "\n"))
      |> Kernel.+(1)

    column =
      prefix
      |> String.split("\n")
      |> List.last()
      |> then(&String.length(&1 || ""))

    {line_number, column}
  end

  defp constraint_error_message?(message) do
    String.starts_with?(message, "constraint ") and String.contains?(message, " does not exist")
  end

  defp constraint_name(message) do
    case Regex.run(~r/constraint "([^"]+)"/, message) do
      [_match, name] -> name
      nil -> nil
    end
  end

  defp constraint_table(message) do
    case Regex.run(~r/for table "([^"]+)"/, message) do
      [_match, name] -> name
      nil -> nil
    end
  end
end
