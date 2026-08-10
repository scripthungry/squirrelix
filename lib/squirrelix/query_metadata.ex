defmodule Squirrelix.QueryMetadata do
  @moduledoc false

  # Typed ingress for metadata-file entries and Inferrer results.
  # Wire format remains keyword lists / maps in `.exs` files; `parse/2` is the
  # single normalisation boundary into `%Column{}` and typed params.

  alias Squirrelix.Column
  alias Squirrelix.Error.InvalidReturnColumn
  alias Squirrelix.Error.MissingQueryMetadataField
  alias Squirrelix.Error.ParameterArityMismatch
  alias Squirrelix.Query
  alias Squirrelix.SQL
  alias Squirrelix.TypeMapper

  @enforce_keys [:params, :returns]
  defstruct [:params, :returns]

  @type param :: %{type: TypeMapper.elixir_type(), name: String.t() | nil}
  @type t :: %__MODULE__{params: [param()], returns: [Column.t()]}

  @type parse_error ::
          MissingQueryMetadataField.t()
          | InvalidReturnColumn.t()
          | ParameterArityMismatch.t()
          | struct()

  @doc """
  Parses a metadata/inferrer keyword into a `%QueryMetadata{}`.

  Accepts the historical keyword shape `[params: types, returns: columns]` and
  richer param entries `%{type: type, name: optional_name}`. Return columns may
  be `%Column{}` or maps with `:name`, `:type`, and boolean `:nullable?`.
  """
  @spec parse(keyword(), Query.t()) :: {:ok, t()} | {:error, parse_error()}
  def parse(opts, %Query{} = query) when is_list(opts) do
    with {:ok, raw_params} <- fetch_field(query, opts, :params),
         {:ok, raw_returns} <- fetch_field(query, opts, :returns),
         {:ok, params} <- normalize_params(raw_params, query),
         {:ok, returns} <- normalize_returns(raw_returns, query),
         :ok <- validate_param_arity(query, params) do
      {:ok, %__MODULE__{params: params, returns: returns}}
    end
  end

  def parse(_other, %Query{} = query) do
    {:error, %MissingQueryMetadataField{file: query.file, field: :params}}
  end

  defp fetch_field(query, opts, field) do
    case Keyword.fetch(opts, field) do
      {:ok, value} when is_list(value) -> {:ok, value}
      {:ok, _value} -> {:error, %MissingQueryMetadataField{file: query.file, field: field}}
      :error -> {:error, %MissingQueryMetadataField{file: query.file, field: field}}
    end
  end

  defp normalize_params(params, query) do
    case traverse(params, &normalize_param/1) do
      {:ok, _} = ok ->
        ok

      {:error, :invalid_param_name} ->
        {:error, %MissingQueryMetadataField{file: query.file, field: :params}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_param(%{type: type} = entry) do
    name = Map.get(entry, :name)

    with {:ok, type} <- TypeMapper.normalize_type(type) do
      if is_nil(name) or is_binary(name) do
        {:ok, %{type: type, name: name}}
      else
        {:error, :invalid_param_name}
      end
    end
  end

  defp normalize_param(type) do
    with {:ok, type} <- TypeMapper.normalize_type(type) do
      {:ok, %{type: type, name: nil}}
    end
  end

  defp normalize_returns(returns, query) do
    traverse(returns, &normalize_return(&1, query))
  end

  defp normalize_return(column, query) do
    case Column.cast(column) do
      {:ok, %Column{} = column} ->
        with :ok <- validate_column_name(column.name, query),
             {:ok, type} <- TypeMapper.normalize_type(column.type) do
          {:ok, %Column{column | type: type}}
        end

      {:error, reason} ->
        {:error,
         %InvalidReturnColumn{
           file: query.file,
           starting_line: query.starting_line,
           content: query.content,
           reason: reason
         }}
    end
  end

  defp validate_column_name(name, query) do
    case SQL.identifier_error(name) do
      nil ->
        :ok

      reason ->
        {:error,
         %Squirrelix.Error.QueryHasInvalidColumn{
           file: query.file,
           starting_line: query.starting_line,
           content: query.content,
           column_name: name,
           reason: reason,
           suggested_name: SQL.similar_identifier(name)
         }}
    end
  end

  defp validate_param_arity(%Query{content: content} = query, params) do
    expected = SQL.max_parameter_index(content)
    got = length(params)

    cond do
      expected == 0 and got == 0 ->
        :ok

      expected == got ->
        :ok

      true ->
        {:error,
         %ParameterArityMismatch{
           file: query.file,
           starting_line: query.starting_line,
           content: query.content,
           expected: expected,
           got: got
         }}
    end
  end

  defp traverse(values, mapper) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, mapped_values} ->
      case mapper.(value) do
        {:ok, mapped_value} -> {:cont, {:ok, [mapped_value | mapped_values]}}
        {:error, :invalid_param_name} -> {:halt, {:error, :invalid_param_name}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, mapped_values} -> {:ok, Enum.reverse(mapped_values)}
      {:error, :invalid_param_name} -> {:error, :invalid_param_name}
      {:error, error} -> {:error, error}
    end
  end
end
