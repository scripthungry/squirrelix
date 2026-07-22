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

defmodule Squirrelixir.TypedQuery do
  @moduledoc """
  A query annotated with parameter and return column metadata.
  """

  @enforce_keys [:file, :starting_line, :name, :comment, :content, :params, :returns]
  defstruct [:file, :starting_line, :name, :comment, :content, :params, :returns]

  alias Squirrelixir.Column
  alias Squirrelixir.Error.DuplicateReturnColumns
  alias Squirrelixir.Error.MissingQueryMetadataField
  alias Squirrelixir.Error.QueryHasInvalidColumn
  alias Squirrelixir.Parameter
  alias Squirrelixir.Query
  alias Squirrelixir.SQL
  alias Squirrelixir.TypeMapper

  @reserved_argument_names MapSet.new(~w(
    after and catch cond do else end false fn for if in nil not or receive rescue true try unless when with
  ))

  @sql_literal_argument_names MapSet.new(~w(false nil null true))

  @type t :: %__MODULE__{
          file: String.t(),
          starting_line: pos_integer(),
          name: String.t(),
          comment: [String.t()],
          content: String.t(),
          params: [Parameter.t()],
          returns: [Column.t()]
        }

  @spec from_query(Query.t(), keyword()) ::
          {:ok, t()}
          | {:error,
             DuplicateReturnColumns.t()
             | MissingQueryMetadataField.t()
             | QueryHasInvalidColumn.t()
             | struct()}
  def from_query(%Query{} = query, opts) when is_list(opts) do
    with {:ok, params} <- fetch_metadata_field(query, opts, :params),
         {:ok, returns} <- fetch_metadata_field(query, opts, :returns),
         {:ok, params} <- normalize_params(params),
         {:ok, returns} <- normalize_returns(returns, query) do
      case duplicate_column_names(returns) do
        [] ->
          {:ok,
           %__MODULE__{
             file: query.file,
             starting_line: query.starting_line,
             name: query.name,
             comment: query.comment,
             content: query.content,
             params: parameters(query.content, params),
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
  end

  @spec resolve_parameter_names([Parameter.t()]) :: [String.t()]
  def resolve_parameter_names(params) when is_list(params) do
    params
    |> Enum.reduce({[], MapSet.new(["connection"])}, fn param, {names, used} ->
      name = param |> preferred_argument_name() |> safe_argument_name(param.index, used)
      name = unique_argument_name(name, used, param.index)
      {[name | names], MapSet.put(used, name)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp fetch_metadata_field(query, opts, field) do
    case Keyword.fetch(opts, field) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, %MissingQueryMetadataField{file: query.file, field: field}}
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

  defp normalize_params(params) do
    traverse(params, &TypeMapper.normalize_type/1)
  end

  defp normalize_returns(returns, query) do
    traverse(returns, &column(&1, query))
  end

  defp traverse(values, mapper) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, mapped_values} ->
      case mapper.(value) do
        {:ok, mapped_value} -> {:cont, {:ok, [mapped_value | mapped_values]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, mapped_values} -> {:ok, Enum.reverse(mapped_values)}
      {:error, error} -> {:error, error}
    end
  end

  defp column(%Column{} = column, query) do
    with :ok <- validate_column_name(column.name, query),
         {:ok, type} <- TypeMapper.normalize_type(column.type) do
      {:ok, %Column{column | type: type}}
    end
  end

  defp column(%{name: name, type: type, nullable?: nullable?}, query) do
    with :ok <- validate_column_name(name, query),
         {:ok, type} <- TypeMapper.normalize_type(type) do
      {:ok, %Column{name: name, type: type, nullable?: nullable?}}
    end
  end

  defp validate_column_name(name, query) do
    case column_name_error(name) do
      nil -> :ok
      reason -> {:error, invalid_column_error(query, name, reason)}
    end
  end

  defp column_name_error(name) do
    cond do
      name == "" -> :empty
      not SQL.valid_identifier?(name) -> column_name_grapheme_error(name)
      true -> nil
    end
  end

  defp column_name_grapheme_error(name) do
    case String.graphemes(name) do
      [] ->
        :empty

      [first | rest] ->
        if first == "_" or lowercase_letter?(first) do
          invalid_grapheme_in_rest(rest, 1, name)
        else
          {:invalid_grapheme, 0, first}
        end
    end
  end

  defp invalid_grapheme_in_rest([], _position, _name), do: {:invalid_grapheme, 0, ""}

  defp invalid_grapheme_in_rest([grapheme | rest], position, name) do
    if identifier_grapheme?(grapheme) do
      invalid_grapheme_in_rest(rest, position + 1, name)
    else
      {:invalid_grapheme, position, grapheme}
    end
  end

  defp invalid_column_error(query, column_name, reason) do
    %QueryHasInvalidColumn{
      file: query.file,
      starting_line: query.starting_line,
      content: query.content,
      column_name: column_name,
      reason: reason,
      suggested_name: SQL.similar_identifier(column_name)
    }
  end

  defp preferred_argument_name(%Parameter{name: nil, index: index}), do: "arg_#{index}"
  defp preferred_argument_name(%Parameter{name: name}) when is_binary(name), do: name

  defp safe_argument_name(name, index, used) do
    cond do
      not SQL.valid_identifier?(name) ->
        "arg_#{index}"

      MapSet.member?(@sql_literal_argument_names, name) ->
        "arg_#{index}"

      MapSet.member?(@reserved_argument_names, name) ->
        "#{name}_"

      shadowing_helper_name?(name) ->
        rename_shadowed_name(name, used)

      true ->
        name
    end
  end

  defp shadowing_helper_name?(name) do
    String.ends_with?(name, "decoder") or String.ends_with?(name, "encoder")
  end

  defp rename_shadowed_name(name, used, tries \\ 1) do
    candidate = "#{name}_#{tries}"

    if MapSet.member?(used, candidate) do
      rename_shadowed_name(name, used, tries + 1)
    else
      candidate
    end
  end

  defp unique_argument_name(name, used, _fallback_index) do
    if MapSet.member?(used, name) do
      rename_shadowed_name(name, used)
    else
      name
    end
  end

  defp identifier_grapheme?(grapheme) do
    grapheme == "_" or lowercase_letter?(grapheme) or digit?(grapheme)
  end

  defp lowercase_letter?(<<char::utf8>>), do: char in ?a..?z
  defp lowercase_letter?(_), do: false

  defp digit?(<<char::utf8>>), do: char in ?0..?9
  defp digit?(_), do: false

  defp duplicate_column_names(columns) do
    columns
    |> Enum.frequencies_by(& &1.name)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> Enum.sort()
  end
end
