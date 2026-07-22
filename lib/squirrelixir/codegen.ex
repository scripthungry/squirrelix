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
  alias Squirrelixir.TypeMapper

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

    #{queries |> Enum.sort_by(& &1.file) |> Enum.map(&function_source(&1, postgrex_module)) |> join_function_sources()}
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

      {:error, :invalid_sql_directory} ->
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

      {:error, :invalid_sql_directory} ->
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
    args = TypedQuery.resolve_parameter_names(query.params)
    all_args = ["connection" | args]
    encoded_params = encode_params_call(args, query.params)

    """
      #{doc_source(query)}
      #{row_type_source(query)}@spec #{query.name}(Postgrex.conn()#{spec_args(query.params)}) :: #{function_return_typespec(query)}
      def #{query.name}(#{Enum.join(all_args, ", ")}) do
        connection
        |> #{inspect(postgrex_module)}.query!(#{sql_string_literal(query.content)}, #{encoded_params})
        |> #{decode_call(query.returns)}
      end
    """
  end

  defp encode_params_call([], []), do: "[]"

  defp encode_params_call(args, params) do
    args
    |> Enum.zip(params)
    |> Enum.map(fn {name, %Parameter{type: type}} ->
      "encode_value(#{name}, #{inspect(type, limit: :infinity)})"
    end)
    |> then(&"[#{Enum.join(&1, ", ")}]")
  end

  defp decode_helpers([]), do: ""

  defp decode_helpers(queries) do
    queries
    |> runtime_helper_sources()
    |> Enum.join("\n")
  end

  defp runtime_helper_sources(queries) do
    types = runtime_types(queries)

    []
    |> maybe_add_command_helper(queries)
    |> maybe_add_rows_helper(queries)
    |> maybe_add_encode_helpers(queries)
    |> maybe_add_uuid_helpers(types)
    |> Enum.reverse()
  end

  defp runtime_types(queries) do
    queries
    |> Enum.flat_map(fn query ->
      Enum.map(query.params, & &1.type) ++ Enum.map(query.returns, & &1.type)
    end)
    |> MapSet.new()
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
      types = runtime_types(queries)

      [
        """
          defp decode_rows(%Postgrex.Result{rows: rows}, columns) do
            Enum.map(rows, &decode_row(&1, columns))
          end

          defp decode_row(row, columns) do
            columns
            |> Enum.zip(row)
            |> Map.new(fn {{name, type, nullable?}, value} ->
              {name, decode_value(value, type, nullable?)}
            end)
          end

          defp decode_value(value, _type, true) when is_nil(value), do: nil
          defp decode_value(value, type, _nullable?), do: decode_scalar(value, type)

          #{decode_type_clauses(types)}
        """
        | sources
      ]
    else
      sources
    end
  end

  defp decode_type_clauses(types) do
    types
    |> then(fn types ->
      []
      |> add_type_clause(types, :integer, "defp decode_scalar(value, :integer), do: value")
      |> add_type_clause(types, :string, "defp decode_scalar(value, :string), do: value")
      |> add_type_clause(types, :boolean, "defp decode_scalar(value, :boolean), do: value")
      |> add_type_clause(types, :float, "defp decode_scalar(value, :float), do: value")
      |> add_type_clause(types, :decimal, "defp decode_scalar(value, :decimal), do: value")
      |> add_type_clause(types, :binary, "defp decode_scalar(value, :binary), do: value")
      |> add_type_clause(types, :date, "defp decode_scalar(value, :date), do: value")
      |> add_type_clause(types, :time, "defp decode_scalar(value, :time), do: value")
      |> add_type_clause(
        types,
        :naive_datetime,
        "defp decode_scalar(value, :naive_datetime), do: value"
      )
      |> add_type_clause(
        types,
        :utc_datetime,
        "defp decode_scalar(value, :utc_datetime), do: value"
      )
      |> add_type_clause(
        types,
        :map,
        """
        defp decode_scalar(value, :map) when is_map(value), do: value
        defp decode_scalar(value, :map) when is_binary(value), do: JSON.decode!(value)
        """
      )
      |> add_type_clause(
        types,
        :uuid,
        """
        defp decode_scalar(value, :uuid) when is_binary(value) and byte_size(value) == 16,
          do: uuid_to_string(value)

        defp decode_scalar(value, :uuid), do: value
        """
      )
      |> add_list_type_clauses(types)
    end)
    |> Enum.reverse()
    |> Kernel.++([
      "defp decode_scalar(value, _type), do: value"
    ])
    |> Enum.join("\n")
  end

  defp add_type_clause(clauses, types, type, source) do
    if MapSet.member?(types, type) or list_element_type?(types, type) do
      [source | clauses]
    else
      clauses
    end
  end

  defp add_list_type_clauses(clauses, types) do
    types
    |> Enum.filter(&match?({:list, _}, &1))
    |> Enum.reduce(clauses, fn {:list, type}, clauses ->
      if Enum.any?(clauses, &String.contains?(&1, "{:list, #{inspect(type)}}")) do
        clauses
      else
        [
          "defp decode_scalar(value, {:list, #{inspect(type)}}) when is_list(value), do: Enum.map(value, &decode_scalar(&1, #{inspect(type)}))"
          | clauses
        ]
      end
    end)
  end

  defp maybe_add_encode_helpers(sources, queries) do
    if Enum.any?(queries, &(&1.params != [])) do
      types = runtime_types(queries)

      [
        """
          #{encode_type_clauses(types)}
        """
        | sources
      ]
    else
      sources
    end
  end

  defp encode_type_clauses(types) do
    types
    |> then(fn types ->
      []
      |> add_type_clause(types, :integer, "defp encode_value(value, :integer), do: value")
      |> add_type_clause(types, :string, "defp encode_value(value, :string), do: value")
      |> add_type_clause(types, :boolean, "defp encode_value(value, :boolean), do: value")
      |> add_type_clause(types, :float, "defp encode_value(value, :float), do: value")
      |> add_type_clause(types, :decimal, "defp encode_value(value, :decimal), do: value")
      |> add_type_clause(types, :binary, "defp encode_value(value, :binary), do: value")
      |> add_type_clause(types, :date, "defp encode_value(value, :date), do: value")
      |> add_type_clause(types, :time, "defp encode_value(value, :time), do: value")
      |> add_type_clause(
        types,
        :naive_datetime,
        "defp encode_value(value, :naive_datetime), do: value"
      )
      |> add_type_clause(
        types,
        :utc_datetime,
        "defp encode_value(value, :utc_datetime), do: value"
      )
      |> add_type_clause(
        types,
        :map,
        "defp encode_value(value, :map) when is_map(value), do: JSON.encode!(value)"
      )
      |> add_type_clause(
        types,
        :uuid,
        "defp encode_value(value, :uuid), do: uuid_from_string(value)"
      )
      |> add_list_encode_clauses(types)
    end)
    |> Enum.reverse()
    |> Kernel.++([
      "defp encode_value(nil, _type), do: nil",
      "defp encode_value(value, _type), do: value"
    ])
    |> Enum.join("\n")
  end

  defp add_list_encode_clauses(clauses, types) do
    types
    |> Enum.filter(&match?({:list, _}, &1))
    |> Enum.reduce(clauses, fn {:list, type}, clauses ->
      if Enum.any?(clauses, &String.contains?(&1, "{:list, #{inspect(type)}}")) do
        clauses
      else
        [
          "defp encode_value(value, {:list, #{inspect(type)}}) when is_list(value), do: Enum.map(value, &encode_value(&1, #{inspect(type)}))"
          | clauses
        ]
      end
    end)
  end

  defp maybe_add_uuid_helpers(sources, types) do
    if MapSet.member?(types, :uuid) or list_element_type?(types, :uuid) do
      [
        """
          defp uuid_to_string(uuid) when is_binary(uuid) and byte_size(uuid) == 16 do
            hex = Base.encode16(uuid, case: :lower)

            <<part1::binary-size(8), part2::binary-size(4), part3::binary-size(4),
              part4::binary-size(4), part5::binary>> = hex

            "\#{part1}-\#{part2}-\#{part3}-\#{part4}-\#{part5}"
          end

          defp uuid_from_string(string) when is_binary(string) do
            case Base.decode16(String.replace(string, "-", ""), case: :mixed) do
              {:ok, <<_::128>> = uuid} ->
                uuid

              _ ->
                raise ArgumentError, "invalid UUID: \#{inspect(string)}"
            end
          end
        """
        | sources
      ]
    else
      sources
    end
  end

  defp list_element_type?(types, element_type) do
    Enum.any?(types, fn
      {:list, ^element_type} -> true
      _ -> false
    end)
  end

  defp decode_call([]), do: "decode_command()"
  defp decode_call(columns), do: "decode_rows(#{inspect(return_column_specs(columns))})"

  defp return_column_specs(columns) do
    Enum.map(columns, fn column ->
      {String.to_atom(column.name), column.type, column.nullable?}
    end)
  end

  defp join_function_sources([]), do: ""

  defp join_function_sources(sources) do
    Enum.map_join(sources, "\n\n", &String.trim/1)
  end

  defp doc_source(%TypedQuery{comment: [], returns: [], params: params} = query)
       when length(params) >= 8 do
    generated_function_doc(query)
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
    |> Enum.map(&TypeMapper.typespec(&1.type))
    |> Enum.map_join("", &", #{&1}")
  end

  defp row_type_source(%TypedQuery{returns: []}), do: ""

  defp row_type_source(%TypedQuery{name: name, returns: returns}) do
    """
      @type #{name}_row :: #{TypeMapper.row_typespec(return_column_specs(returns))}
    """
  end

  defp function_return_typespec(%TypedQuery{returns: []}), do: ":ok"

  defp function_return_typespec(%TypedQuery{name: name, returns: _returns}) do
    "[#{name}_row()]"
  end

  defp generated_function_doc(%TypedQuery{name: name, file: file}) do
    """
      @doc \"\"\"
      Runs the `#{name}` query defined in `#{Path.basename(file)}`.
      \"\"\"
    """
  end

  defp sql_string_literal(content) do
    escaped =
      content
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    "\"#{escaped}\""
  end

  defp summary_status(0, []), do: :empty
  defp summary_status(_generated_count, []), do: :ok
  defp summary_status(_generated_count, [_ | _]), do: :error
end
