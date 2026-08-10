defmodule Squirrelix.Parameter do
  @moduledoc false

  @enforce_keys [:index, :type]
  defstruct [:index, :name, :type]

  @type elixir_type :: Squirrelix.TypeMapper.elixir_type()
  @type t :: %__MODULE__{
          index: pos_integer(),
          name: String.t() | nil,
          type: elixir_type()
        }
end

defmodule Squirrelix.Column do
  @moduledoc false

  @enforce_keys [:name, :type, :nullable?]
  defstruct [:name, :type, :nullable?]

  @type elixir_type :: Squirrelix.TypeMapper.elixir_type()
  @type t :: %__MODULE__{
          name: String.t(),
          type: elixir_type(),
          nullable?: boolean()
        }

  @type cast_error :: :missing_nullable | :invalid_shape

  @doc false
  @spec cast(term()) :: {:ok, t()} | {:error, cast_error()}
  def cast(%__MODULE__{} = column), do: {:ok, column}

  def cast(%{name: name, type: type, nullable?: nullable?})
      when is_binary(name) and is_boolean(nullable?) do
    {:ok, %__MODULE__{name: name, type: type, nullable?: nullable?}}
  end

  def cast(%{name: name, type: _type}) when is_binary(name) do
    {:error, :missing_nullable}
  end

  def cast(_other), do: {:error, :invalid_shape}

  @doc false
  @spec to_spec(t()) :: {String.t(), elixir_type(), boolean()}
  def to_spec(%__MODULE__{name: name, type: type, nullable?: nullable?}) do
    {name, type, nullable?}
  end
end

defmodule Squirrelix.TypedQuery do
  @moduledoc false

  @enforce_keys [:file, :starting_line, :name, :comment, :content, :params, :returns]
  defstruct [:file, :starting_line, :name, :comment, :content, :params, :returns]

  alias Squirrelix.Column
  alias Squirrelix.Error
  alias Squirrelix.Error.DuplicateReturnColumns
  alias Squirrelix.Parameter
  alias Squirrelix.Query
  alias Squirrelix.QueryMetadata
  alias Squirrelix.SQL

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
          | {:error, DuplicateReturnColumns.t() | QueryMetadata.parse_error() | struct()}
  def from_query(%Query{} = query, opts) when is_list(opts) do
    with {:ok, %QueryMetadata{} = metadata} <- QueryMetadata.parse(opts, query) do
      case duplicate_column_names(metadata.returns) do
        [] ->
          {:ok,
           %__MODULE__{
             file: query.file,
             starting_line: query.starting_line,
             name: query.name,
             comment: query.comment,
             content: query.content,
             params: build_parameters(query.content, metadata.params),
             returns: metadata.returns
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

  @spec accumulate(Query.t(), keyword(), {[t()], [struct()]}) :: {[t()], [struct()]}
  def accumulate(%Query{} = query, opts, {typed_queries, errors})
      when is_list(opts) and is_list(typed_queries) and is_list(errors) do
    case from_query(query, opts) do
      {:ok, typed_query} -> {[typed_query | typed_queries], errors}
      {:error, error} -> {typed_queries, errors ++ [Error.attach_query(error, query)]}
    end
  end

  @doc """
  Resolve Elixir argument names for parameters.

  `reserved` must include the codegen first argument (`conn` / `repo`) and any
  inlined runtime helper names. Callers typically pass
  `Squirrelix.Codegen.Target.reserved_argument_names/1`.
  """
  @spec resolve_parameter_names([Parameter.t()], Enumerable.t()) :: [String.t()]
  def resolve_parameter_names(params, reserved \\ ["conn"])
      when is_list(params) do
    used = MapSet.new(reserved)

    params
    |> Enum.reduce({[], used}, fn param, {names, used} ->
      name = param |> preferred_argument_name() |> safe_argument_name(param.index, used)
      name = unique_argument_name(name, used, param.index)
      {[name | names], MapSet.put(used, name)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp build_parameters(sql, params) do
    inferred_names = SQL.infer_parameter_names(sql)

    params
    |> Enum.with_index(1)
    |> Enum.map(fn {%{type: type, name: explicit_name}, index} ->
      name = explicit_name || Map.get(inferred_names, index)
      %Parameter{index: index, name: name, type: type}
    end)
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
    # Suffix rule is independent of the helper inventory: generated helpers
    # historically use `*_decoder` / `*_encoder` names, and callers pass the
    # concrete reserved set (see `Codegen.Runtime.reserved_names/0`).
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

  defp duplicate_column_names(columns) do
    columns
    |> Enum.frequencies_by(& &1.name)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> name end)
    |> Enum.sort()
  end
end
