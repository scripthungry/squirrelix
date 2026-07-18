defmodule Squirrelixir.CodegenSummary do
  @moduledoc """
  Summary of a generated query-module write pass.
  """

  @enforce_keys [:generated_count, :errors, :status]
  defstruct [:generated_count, :errors, :status]

  @type t :: %__MODULE__{
          generated_count: non_neg_integer(),
          errors: [{Path.t(), term()}],
          status: :empty | :ok | :error
        }
end

defmodule Squirrelixir.CodegenCheckSummary do
  @moduledoc """
  Summary of a generated query-module check pass.
  """

  @enforce_keys [:checked_count, :errors, :status]
  defstruct [:checked_count, :errors, :status]

  @type t :: %__MODULE__{
          checked_count: non_neg_integer(),
          errors: [{Path.t(), term()}],
          status: :empty | :ok | :error
        }
end

defmodule Squirrelixir.Codegen do
  @moduledoc """
  Generates Elixir modules for typed SQL queries.
  """

  alias Squirrelixir.Output
  alias Squirrelixir.Parameter
  alias Squirrelixir.Project
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

  @spec generate_module(module(), [TypedQuery.t()], keyword()) :: String.t()
  def generate_module(module, queries, opts \\ []) when is_atom(module) and is_list(queries) do
    version = Keyword.fetch!(opts, :version)
    postgrex_module = Keyword.get(opts, :postgrex, Postgrex)

    source = """
    defmodule #{inspect(module)} do
      @moduledoc \"\"\"
      This module contains generated query functions.

      > This module was generated automatically using Squirrelixir #{version}.
      \"\"\"

    #{queries |> Enum.sort_by(& &1.file) |> Enum.map_join("\n\n", &function_source(&1, postgrex_module))}
    #{decode_helpers(queries)}
    end
    """

    source
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  @spec write_directory(Path.t(), Path.t(), [TypedQuery.t()], keyword()) ::
          :ok | {:error, :invalid_sql_directory | struct()}
  def write_directory(root, sql_directory, queries, opts \\ [])
      when is_binary(root) and is_binary(sql_directory) and is_list(queries) and is_list(opts) do
    case Project.module_for_sql_directory(root, sql_directory) do
      {:ok, module} ->
        content = generate_module(module, queries, opts)
        output_file = sql_directory |> Path.dirname() |> Path.join("sql.ex")

        Output.safe_write(output_file, content)

      :error ->
        {:error, :invalid_sql_directory}
    end
  end

  @spec check_directory(Path.t(), Path.t(), [TypedQuery.t()], keyword()) ::
          :ok | {:error, :invalid_sql_directory | struct()}
  def check_directory(root, sql_directory, queries, opts \\ [])
      when is_binary(root) and is_binary(sql_directory) and is_list(queries) and is_list(opts) do
    case Project.module_for_sql_directory(root, sql_directory) do
      {:ok, module} ->
        content = generate_module(module, queries, opts)
        output_file = sql_directory |> Path.dirname() |> Path.join("sql.ex")

        Output.check_file(output_file, content)

      :error ->
        {:error, :invalid_sql_directory}
    end
  end

  @spec write_directories(Path.t(), [TypedQueryDirectory.t()], keyword()) :: [
          {Path.t(), :ok | {:error, :invalid_sql_directory | struct()}, non_neg_integer()}
        ]
  def write_directories(root, directories, opts \\ [])
      when is_binary(root) and is_list(directories) and is_list(opts) do
    directories
    |> Enum.sort_by(& &1.directory)
    |> Enum.map(fn %TypedQueryDirectory{directory: directory, queries: queries} ->
      {directory, write_directory(root, directory, queries, opts), length(queries)}
    end)
  end

  @spec check_directories(Path.t(), [TypedQueryDirectory.t()], keyword()) :: [
          {Path.t(), :ok | {:error, :invalid_sql_directory | struct()}, non_neg_integer()}
        ]
  def check_directories(root, directories, opts \\ [])
      when is_binary(root) and is_list(directories) and is_list(opts) do
    directories
    |> Enum.sort_by(& &1.directory)
    |> Enum.map(fn %TypedQueryDirectory{directory: directory, queries: queries} ->
      {directory, check_directory(root, directory, queries, opts), length(queries)}
    end)
  end

  @spec summarize_write_outcomes([{Path.t(), :ok | {:error, term()}, non_neg_integer()}]) ::
          Squirrelixir.CodegenSummary.t()
  def summarize_write_outcomes(outcomes) when is_list(outcomes) do
    {generated_count, errors} =
      Enum.reduce(outcomes, {0, []}, fn
        {_directory, :ok, query_count}, {generated_count, errors} ->
          {generated_count + query_count, errors}

        {directory, {:error, error}, _query_count}, {generated_count, errors} ->
          {generated_count, [{directory, error} | errors]}
      end)

    errors = Enum.reverse(errors)

    %Squirrelixir.CodegenSummary{
      generated_count: generated_count,
      errors: errors,
      status: summary_status(generated_count, errors)
    }
  end

  @spec summarize_check_outcomes([{Path.t(), :ok | {:error, term()}, non_neg_integer()}]) ::
          Squirrelixir.CodegenCheckSummary.t()
  def summarize_check_outcomes(outcomes) when is_list(outcomes) do
    {checked_count, errors} =
      Enum.reduce(outcomes, {0, []}, fn
        {_directory, :ok, query_count}, {checked_count, errors} ->
          {checked_count + query_count, errors}

        {directory, {:error, error}, _query_count}, {checked_count, errors} ->
          {checked_count, [{directory, error} | errors]}
      end)

    errors = Enum.reverse(errors)

    %Squirrelixir.CodegenCheckSummary{
      checked_count: checked_count,
      errors: errors,
      status: summary_status(checked_count, errors)
    }
  end

  defp function_source(%TypedQuery{} = query, postgrex_module) do
    args = argument_names(query.params)
    all_args = ["connection" | args]
    params = Enum.join(args, ", ")

    """
      #{doc_source(query)}
      @spec #{query.name}(Postgrex.conn()#{spec_args(query.params)}) :: #{return_spec(query.returns)}
      def #{query.name}(#{Enum.join(all_args, ", ")}) do
        connection
        |> #{inspect(postgrex_module)}.query!(#{inspect(query.content)}, [#{params}])
        |> #{decode_call(query.returns)}
      end
    """
  end

  defp decode_helpers([]), do: ""

  defp decode_helpers(queries) do
    queries
    |> decode_helper_sources()
    |> Enum.join("\n")
  end

  defp decode_helper_sources(queries) do
    []
    |> maybe_add_command_helper(queries)
    |> maybe_add_rows_helper(queries)
    |> Enum.reverse()
  end

  defp maybe_add_command_helper(sources, queries) do
    if Enum.any?(queries, &(&1.returns == [])) do
      [
        """
          defp decode_command(%Postgrex.Result{}) do
            :ok
          end
        """
        | sources
      ]
    else
      sources
    end
  end

  defp maybe_add_rows_helper(sources, queries) do
    if Enum.any?(queries, &(&1.returns != [])) do
      [
        """
          defp decode_rows(%Postgrex.Result{rows: rows}, columns) do
            Enum.map(rows, &row_to_map(&1, columns))
          end

          defp row_to_map(row, columns) do
            columns
            |> Enum.zip(row)
            |> Map.new()
          end
        """
        | sources
      ]
    else
      sources
    end
  end

  defp decode_call([]), do: "decode_command()"
  defp decode_call(columns), do: "decode_rows(#{inspect(return_column_names(columns))})"

  defp argument_names(params) do
    params
    |> Enum.reduce({[], MapSet.new(["connection"])}, fn param, {names, used} ->
      name = unique_argument_name(preferred_argument_name(param), used, param.index)
      {[name | names], MapSet.put(used, name)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp preferred_argument_name(%Parameter{name: nil, index: index}), do: "arg_#{index}"
  defp preferred_argument_name(%Parameter{name: name}) when is_binary(name), do: name

  defp unique_argument_name(name, used, fallback_index) do
    if MapSet.member?(used, name) do
      fallback_argument_name(fallback_index, used)
    else
      name
    end
  end

  defp fallback_argument_name(index, used) do
    name = "arg_#{index}"

    if MapSet.member?(used, name) do
      fallback_argument_name(index + 1, used)
    else
      name
    end
  end

  defp doc_source(%TypedQuery{comment: []}), do: ""

  defp doc_source(%TypedQuery{comment: comments}) do
    """
      @doc \"\"\"
      #{Enum.join(comments, "\n")}
      \"\"\"
    """
  end

  defp spec_args([]), do: ""

  defp spec_args(params) do
    params
    |> Enum.map(&type_spec(&1.type))
    |> Enum.map_join("", &", #{&1}")
  end

  defp return_spec([]), do: ":ok"

  defp return_spec(columns) do
    columns
    |> Enum.map_join(", ", &column_spec/1)
    |> then(&"[%{#{&1}}]")
  end

  defp column_spec(column) do
    type = type_spec(column.type)
    type = if column.nullable?, do: "#{type} | nil", else: type

    "required(#{inspect(String.to_atom(column.name))}) => #{type}"
  end

  defp return_column_names(columns) do
    Enum.map(columns, &String.to_atom(&1.name))
  end

  defp type_spec(:integer), do: "integer()"
  defp type_spec(:string), do: "String.t()"
  defp type_spec(:boolean), do: "boolean()"
  defp type_spec(:float), do: "float()"
  defp type_spec(:decimal), do: "Decimal.t()"
  defp type_spec(:binary), do: "binary()"
  defp type_spec(:map), do: "map()"
  defp type_spec(:uuid), do: "String.t()"
  defp type_spec(:date), do: "Date.t()"
  defp type_spec(:time), do: "Time.t()"
  defp type_spec(:naive_datetime), do: "NaiveDateTime.t()"
  defp type_spec(:utc_datetime), do: "DateTime.t()"
  defp type_spec({:list, type}), do: "[#{type_spec(type)}]"
  defp type_spec(_type), do: "term()"

  defp summary_status(0, []), do: :empty
  defp summary_status(_generated_count, []), do: :ok
  defp summary_status(_generated_count, [_ | _]), do: :error
end
