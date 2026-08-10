defmodule Squirrelix.SourceRef do
  @moduledoc false

  # Shared query location context for structured errors. Prefer embedding this
  # (or a full `Query.t()`) over repeating `:file` / `:starting_line` / `:content`
  # on every error struct — new errors should use `SourceRef` when possible.

  alias Squirrelix.Query
  alias Squirrelix.TypedQuery

  @enforce_keys [:file, :starting_line, :content]
  defstruct [:file, :starting_line, :content]

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          content: String.t()
        }

  @spec from_query(Query.t()) :: t()
  def from_query(%Query{} = query) do
    %__MODULE__{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content
    }
  end

  @spec from_typed_query(TypedQuery.t()) :: t()
  def from_typed_query(%TypedQuery{} = query) do
    %__MODULE__{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content
    }
  end
end
