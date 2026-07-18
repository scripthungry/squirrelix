defmodule Squirrelixir.Parameter do
  @moduledoc """
  A typed SQL parameter in query order.
  """

  @enforce_keys [:index, :type]
  defstruct [:index, :name, :type]

  @type t :: %__MODULE__{index: pos_integer(), name: String.t() | nil, type: atom()}
end

defmodule Squirrelixir.Column do
  @moduledoc """
  A returned SQL column.
  """

  @enforce_keys [:name, :type, :nullable?]
  defstruct [:name, :type, :nullable?]

  @type t :: %__MODULE__{name: String.t(), type: atom(), nullable?: boolean()}
end

defmodule Squirrelixir.TypedQuery do
  @moduledoc """
  A query annotated with parameter and return column metadata.
  """

  @enforce_keys [:file, :starting_line, :name, :comment, :content, :params, :returns]
  defstruct [:file, :starting_line, :name, :comment, :content, :params, :returns]

  alias Squirrelixir.Column
  alias Squirrelixir.Error.DuplicateReturnColumns
  alias Squirrelixir.Parameter
  alias Squirrelixir.Query
  alias Squirrelixir.SQL

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          name: String.t(),
          comment: [String.t()],
          content: String.t(),
          params: [Parameter.t()],
          returns: [Column.t()]
        }

  @spec from_query(Query.t(), keyword()) :: {:ok, t()} | {:error, DuplicateReturnColumns.t()}
  def from_query(%Query{} = query, opts) when is_list(opts) do
    returns = opts |> Keyword.fetch!(:returns) |> Enum.map(&column/1)

    case duplicate_column_names(returns) do
      [] ->
        {:ok,
         %__MODULE__{
           file: query.file,
           starting_line: query.starting_line,
           name: query.name,
           comment: query.comment,
           content: query.content,
           params: parameters(query.content, Keyword.fetch!(opts, :params)),
           returns: returns
         }}

      names ->
        {:error,
         %DuplicateReturnColumns{
           file: query.file,
           starting_line: query.starting_line,
           content: query.content,
           names: names
         }}
    end
  end

  defp parameters(sql, types) do
    inferred_names = SQL.infer_parameter_names(sql)

    types
    |> Enum.with_index(1)
    |> Enum.map(fn {type, index} ->
      %Parameter{index: index, name: Map.get(inferred_names, index), type: type}
    end)
  end

  defp column(%Column{} = column), do: column

  defp column(%{name: name, type: type, nullable?: nullable?}) do
    %Column{name: name, type: type, nullable?: nullable?}
  end

  defp duplicate_column_names(columns) do
    columns
    |> Enum.frequencies_by(& &1.name)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> Enum.sort()
  end
end
