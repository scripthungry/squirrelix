defmodule Squirrelix.CodegenSummary do
  @moduledoc """
  Summary of a generated query-module write pass.

  Returned by `Squirrelix.generate/3`. Part of the supported public API.
  """

  @enforce_keys [:generated_count, :errors, :status]
  defstruct [:generated_count, :errors, :status]

  @type t :: %__MODULE__{
          generated_count: non_neg_integer(),
          errors: [{Path.t(), term()}],
          status: :empty | :ok | :error
        }
end

defmodule Squirrelix.CodegenCheckSummary do
  @moduledoc """
  Summary of a generated query-module check pass.

  Returned by `Squirrelix.check/3`. Part of the supported public API.
  """

  @enforce_keys [:checked_count, :errors, :status]
  defstruct [:checked_count, :errors, :status]

  @type t :: %__MODULE__{
          checked_count: non_neg_integer(),
          errors: [{Path.t(), term()}],
          status: :empty | :ok | :error
        }
end

defmodule Squirrelix.Codegen do
  @moduledoc false

  alias Squirrelix.Output
  alias Squirrelix.Parameter
  alias Squirrelix.Project
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypeMapper

  require Logger

  @spec generate_module(module(), [TypedQuery.t()], keyword()) :: String.t()
  def generate_module(module, queries, opts \\ []) when is_atom(module) and is_list(queries) do
    version = Keyword.fetch!(opts, :version)
    postgrex_module = Keyword.get(opts, :postgrex, Postgrex)

    sorted_queries = Enum.sort_by(queries, & &1.file)

    source = """
    defmodule #{inspect(module)} do
      @moduledoc \"\"\"
      This module contains generated query functions.

      > This module was generated automatically using Squirrelix #{version}.

      Runtime row decoding uses `column_spec/0` tuples `{name, type, nullable?}`
      where `type` is an atom such as `:string` or a list wrapper such as
      `{:list, :integer}`.

      Each query has a raising function (via `Postgrex.query!/3`) and an additive
      soft companion named `<name>_ok/arity` (via `Postgrex.query/3`) that returns
      `{:ok, result} | {:error, Exception.t()}`. Soft command companions return
      `{:ok, num_rows}` where `num_rows` is the affected-row count.

      Public `@spec`s are Dialyzer-oriented for call sites under typical flags
      (`:underspecs`, `:error_handling`, `:unknown`, `:unmatched_returns`). Enabling
      Dialyzer `:overspecs` / `:specdiffs` may warn that row contracts are more
      precise than success typing of shared decode helpers — that is intentional.
      \"\"\"

      @type column_spec :: {atom(), atom() | {:list, atom()}, boolean()}

    #{sorted_queries |> function_sources(postgrex_module) |> join_function_sources()}#{runtime_helpers_section(queries)}
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
    case prepare_directory(root, sql_directory, queries, opts) do
      {:ok, prepared} -> Output.commit_writes([prepared])
      {:error, reason} -> {:error, reason}
    end
  end

  @spec prepare_directory(Path.t(), Path.t(), [TypedQuery.t()], keyword()) ::
          {:ok, map()} | {:error, :invalid_sql_directory | struct()}
  def prepare_directory(root, sql_directory, queries, opts \\ [])
      when is_binary(root) and is_binary(sql_directory) and is_list(queries) and is_list(opts) do
    case Project.module_for_sql_directory(root, sql_directory) do
      {:ok, module} ->
        content = generate_module(module, queries, opts)
        output_file = sql_directory |> Path.dirname() |> Path.join("sql.ex")
        Output.prepare_write(output_file, content)

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

  @spec summarize_write_outcomes([{Path.t(), :ok | {:error, term()}, non_neg_integer()}]) ::
          Squirrelix.CodegenSummary.t()
  def summarize_write_outcomes(outcomes) when is_list(outcomes) do
    {generated_count, errors} =
      Enum.reduce(outcomes, {0, []}, fn
        {_directory, :ok, query_count}, {generated_count, errors} ->
          {generated_count + query_count, errors}

        {directory, {:error, error}, _query_count}, {generated_count, errors} ->
          {generated_count, [{directory, error} | errors]}
      end)

    errors = Enum.reverse(errors)

    %Squirrelix.CodegenSummary{
      generated_count: generated_count,
      errors: errors,
      status: summary_status(generated_count, errors)
    }
  end

  @spec summarize_check_outcomes([{Path.t(), :ok | {:error, term()}, non_neg_integer()}]) ::
          Squirrelix.CodegenCheckSummary.t()
  def summarize_check_outcomes(outcomes) when is_list(outcomes) do
    {checked_count, errors} =
      Enum.reduce(outcomes, {0, []}, fn
        {_directory, :ok, query_count}, {checked_count, errors} ->
          {checked_count + query_count, errors}

        {directory, {:error, error}, _query_count}, {checked_count, errors} ->
          {checked_count, [{directory, error} | errors]}
      end)

    errors = Enum.reverse(errors)

    %Squirrelix.CodegenCheckSummary{
      checked_count: checked_count,
      errors: errors,
      status: summary_status(checked_count, errors)
    }
  end

  defp function_sources(queries, postgrex_module) do
    taken_names = MapSet.new(queries, & &1.name)
    _ = validate_row_type_names!(queries)

    queries
    |> Enum.reduce({[], taken_names}, fn query, {sources, claimed} ->
      {source, claimed} = function_source(query, postgrex_module, claimed)
      {[source | sources], claimed}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp function_source(%TypedQuery{} = query, postgrex_module, claimed_names) do
    raising = raising_function_source(query, postgrex_module)

    case soft_companion_name(query.name, claimed_names) do
      {:ok, soft_name} ->
        source = raising <> "\n\n" <> soft_function_source(query, postgrex_module, soft_name)
        {source, MapSet.put(claimed_names, soft_name)}

      :skipped ->
        {raising, claimed_names}
    end
  end

  defp raising_function_source(%TypedQuery{} = query, postgrex_module) do
    args = TypedQuery.resolve_parameter_names(query.params)
    all_args = ["conn" | args]
    encoded_params = encode_params_call(args, query.params)

    """
      #{doc_source(query)}
      #{row_type_source(query)}@spec #{query.name}(Postgrex.conn()#{spec_args(query.params)}) :: #{function_return_typespec(query)}
      def #{query.name}(#{Enum.join(all_args, ", ")}) do
        conn
        |> #{inspect(postgrex_module)}.query!(#{sql_string_literal(query.content)}, #{encoded_params})
        |> #{decode_call(query.returns)}
      end
    """
  end

  defp soft_function_source(%TypedQuery{} = query, postgrex_module, soft_name) do
    args = TypedQuery.resolve_parameter_names(query.params)
    all_args = ["conn" | args]
    encoded_params = encode_params_call(args, query.params)
    arity = length(all_args)

    """
      #{soft_doc_source(query, arity)}
      @spec #{soft_name}(Postgrex.conn()#{spec_args(query.params)}) :: #{soft_function_return_typespec(query)}
      def #{soft_name}(#{Enum.join(all_args, ", ")}) do
        case #{inspect(postgrex_module)}.query(conn, #{sql_string_literal(query.content)}, #{encoded_params}) do
          {:ok, result} -> {:ok, result |> #{soft_decode_call(query.returns)}}
          {:error, reason} -> {:error, reason}
        end
      end
    """
  end

  defp soft_companion_name(name, claimed_names) when is_binary(name) do
    soft_name = soft_companion_base_name(name)

    if MapSet.member?(claimed_names, soft_name) do
      Logger.warning(
        "Squirrelix: omitting soft companion `#{soft_name}` for query `#{name}` because that name is already taken"
      )

      :skipped
    else
      {:ok, soft_name}
    end
  end

  defp soft_companion_base_name(name) when is_binary(name) do
    identifier_base_name(name) <> "_ok"
  end

  # Strip trailing `!` / `?` so generated `@type` names stay valid Elixir identifiers.
  defp identifier_base_name(name) when is_binary(name) do
    cond do
      String.ends_with?(name, "!") -> String.trim_trailing(name, "!")
      String.ends_with?(name, "?") -> String.trim_trailing(name, "?")
      true -> name
    end
  end

  defp row_type_name(%TypedQuery{name: name}), do: identifier_base_name(name) <> "_row"

  defp validate_row_type_names!(queries) do
    queries
    |> Enum.filter(&(&1.returns != []))
    |> Enum.reduce(%{}, fn query, seen ->
      type_name = row_type_name(query)

      case Map.fetch(seen, type_name) do
        {:ok, other} ->
          raise ArgumentError,
                "row type name collision on `#{type_name}` between queries `#{other}` and `#{query.name}`"

        :error ->
          Map.put(seen, type_name, query.name)
      end
    end)
  end

  defp soft_doc_source(%TypedQuery{name: name, returns: []}, arity) do
    doc =
      "Soft companion to `#{name}/#{arity}`. Returns `{:ok, num_rows}` or `{:error, exception}` instead of raising."

    "  @doc #{inspect(doc, limit: :infinity)}\n"
  end

  defp soft_doc_source(%TypedQuery{name: name}, arity) do
    doc =
      "Soft companion to `#{name}/#{arity}`. Returns `{:ok, rows}` or `{:error, exception}` instead of raising."

    "  @doc #{inspect(doc, limit: :infinity)}\n"
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

  @runtime_helpers_header "# --- Runtime helpers ---"

  defp runtime_helpers_section([]), do: ""

  defp runtime_helpers_section(queries) do
    case runtime_helper_sources(queries) do
      [] ->
        ""

      sources ->
        """

        #{@runtime_helpers_header}

        #{Enum.join(sources, "\n\n")}
        """
    end
  end

  defp runtime_helper_sources(queries) do
    []
    |> maybe_add_command_helper(queries)
    |> maybe_add_rows_helper(queries)
    |> maybe_add_encode_helpers(queries)
    |> maybe_add_uuid_helpers(queries)
    |> Enum.reverse()
  end

  defp param_types(queries) do
    queries
    |> Enum.flat_map(fn query -> Enum.map(query.params, & &1.type) end)
    |> MapSet.new()
  end

  defp return_types(queries) do
    queries
    |> Enum.flat_map(fn query -> Enum.map(query.returns, & &1.type) end)
    |> MapSet.new()
  end

  defp maybe_add_command_helper(sources, queries) do
    if Enum.any?(queries, &(&1.returns == [])) do
      [
        """
          @spec decode_command(Postgrex.Result.t()) :: :ok
          defp decode_command(%Postgrex.Result{}) do
            :ok
          end

          @spec decode_command_num_rows(Postgrex.Result.t()) :: non_neg_integer()
          defp decode_command_num_rows(%Postgrex.Result{num_rows: num_rows})
               when is_integer(num_rows) and num_rows >= 0 do
            num_rows
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
      types = return_types(queries)

      [
        """
          defp decode_rows(%Postgrex.Result{rows: rows}, column_specs) do
            Enum.map(rows, &decode_row(&1, column_specs))
          end

          defp decode_row(row, column_specs) do
            column_specs
            |> Enum.zip(row)
            |> Map.new(fn {{name, type, nullable?}, value} ->
              {name, decode_column_value(value, type, nullable?)}
            end)
          end

          defp decode_column_value(value, _type, true) when is_nil(value), do: nil
          defp decode_column_value(value, type, _nullable?), do: decode_scalar(value, type)

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
      types = param_types(queries)

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
      |> add_type_clause(types, :integer, encode_scalar_clause(:integer, "is_integer(value)"))
      |> add_type_clause(types, :string, encode_scalar_clause(:string, "is_binary(value)"))
      |> add_type_clause(types, :boolean, encode_scalar_clause(:boolean, "is_boolean(value)"))
      |> add_type_clause(types, :float, encode_scalar_clause(:float, "is_float(value)"))
      |> add_type_clause(
        types,
        :decimal,
        encode_struct_clause(:decimal, "Decimal", "Decimal.t()")
      )
      |> add_type_clause(types, :binary, encode_scalar_clause(:binary, "is_binary(value)"))
      |> add_type_clause(types, :date, encode_struct_clause(:date, "Date", "Date.t()"))
      |> add_type_clause(types, :time, encode_struct_clause(:time, "Time", "Time.t()"))
      |> add_type_clause(
        types,
        :naive_datetime,
        encode_struct_clause(:naive_datetime, "NaiveDateTime", "NaiveDateTime.t()")
      )
      |> add_type_clause(
        types,
        :utc_datetime,
        encode_struct_clause(:utc_datetime, "DateTime", "DateTime.t()")
      )
      |> add_type_clause(
        types,
        :map,
        """
        @spec encode_value(term(), :map) :: binary()
        defp encode_value(value, :map), do: JSON.encode!(value)
        """
      )
      |> add_type_clause(
        types,
        :uuid,
        """
        @spec encode_value(String.t(), :uuid) :: <<_::128>>
        defp encode_value(value, :uuid) when is_binary(value), do: uuid_from_string(value)
        """
      )
      |> add_list_encode_clauses(types)
    end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp encode_scalar_clause(type, guard) do
    typespec = TypeMapper.typespec(type)

    """
    @spec encode_value(#{typespec}, #{inspect(type)}) :: #{typespec}
    defp encode_value(value, #{inspect(type)}) when #{guard}, do: value
    """
  end

  defp encode_struct_clause(type, struct_mod, typespec) do
    """
    @spec encode_value(#{typespec}, #{inspect(type)}) :: #{typespec}
    defp encode_value(value, #{inspect(type)}) when is_struct(value, #{struct_mod}), do: value
    """
  end

  defp add_list_encode_clauses(clauses, types) do
    types
    |> Enum.filter(&match?({:list, _}, &1))
    |> Enum.reduce(clauses, fn {:list, type}, clauses ->
      marker = "{:list, #{inspect(type)}}"

      if Enum.any?(clauses, &String.contains?(&1, marker)) do
        clauses
      else
        inner = TypeMapper.typespec(type)

        [
          """
          @spec encode_value([#{inner}], #{marker}) :: [#{inner}]
          defp encode_value(value, #{marker}) when is_list(value), do: Enum.map(value, &encode_value(&1, #{inspect(type)}))
          """
          | clauses
        ]
      end
    end)
  end

  defp maybe_add_uuid_helpers(sources, queries) do
    param_type_set = param_types(queries)
    return_type_set = return_types(queries)

    encode_uuid? =
      MapSet.member?(param_type_set, :uuid) or list_element_type?(param_type_set, :uuid)

    decode_uuid? =
      MapSet.member?(return_type_set, :uuid) or list_element_type?(return_type_set, :uuid)

    case {encode_uuid?, decode_uuid?} do
      {false, false} ->
        sources

      {encode_uuid?, decode_uuid?} ->
        [uuid_helper_source(encode_uuid?, decode_uuid?) | sources]
    end
  end

  defp uuid_helper_source(true, true) do
    """
      @spec uuid_to_string(<<_::128>>) :: String.t()
      defp uuid_to_string(uuid) when is_binary(uuid) and byte_size(uuid) == 16 do
        hex = Base.encode16(uuid, case: :lower)

        <<part1::binary-size(8), part2::binary-size(4), part3::binary-size(4),
          part4::binary-size(4), part5::binary>> = hex

        "\#{part1}-\#{part2}-\#{part3}-\#{part4}-\#{part5}"
      end

      @spec uuid_from_string(binary()) :: <<_::128>>
      defp uuid_from_string(string) when is_binary(string) do
        case Base.decode16(String.replace(string, "-", ""), case: :mixed) do
          {:ok, <<_::128>> = uuid} ->
            uuid

          _ ->
            raise ArgumentError, "invalid UUID: \#{inspect(string)}"
        end
      end
    """
  end

  defp uuid_helper_source(true, false) do
    """
      @spec uuid_from_string(binary()) :: <<_::128>>
      defp uuid_from_string(string) when is_binary(string) do
        case Base.decode16(String.replace(string, "-", ""), case: :mixed) do
          {:ok, <<_::128>> = uuid} ->
            uuid

          _ ->
            raise ArgumentError, "invalid UUID: \#{inspect(string)}"
        end
      end
    """
  end

  defp uuid_helper_source(false, true) do
    """
      @spec uuid_to_string(<<_::128>>) :: String.t()
      defp uuid_to_string(uuid) when is_binary(uuid) and byte_size(uuid) == 16 do
        hex = Base.encode16(uuid, case: :lower)

        <<part1::binary-size(8), part2::binary-size(4), part3::binary-size(4),
          part4::binary-size(4), part5::binary>> = hex

        "\#{part1}-\#{part2}-\#{part3}-\#{part4}-\#{part5}"
      end
    """
  end

  defp list_element_type?(types, element_type) do
    Enum.any?(types, fn
      {:list, ^element_type} -> true
      _ -> false
    end)
  end

  defp decode_call([]), do: "decode_command()"

  defp decode_call(columns) do
    "decode_rows(#{column_specs_literal(columns)})"
  end

  defp soft_decode_call([]), do: "decode_command_num_rows()"

  defp soft_decode_call(columns), do: decode_call(columns)

  defp soft_function_return_typespec(%TypedQuery{returns: []}) do
    "{:ok, non_neg_integer()} | {:error, Exception.t()}"
  end

  defp soft_function_return_typespec(%TypedQuery{} = query) do
    "{:ok, [#{row_type_name(query)}()]} | {:error, Exception.t()}"
  end

  defp column_specs_literal(columns) do
    columns
    |> Enum.map_join(", ", fn column ->
      "{#{atom_literal(column.name)}, #{inspect(column.type, limit: :infinity)}, #{inspect(column.nullable?)}}"
    end)
    |> then(&"[#{&1}]")
  end

  # Validated snake_case identifiers — emit `:name` without creating Mix VM atoms.
  defp atom_literal(name) when is_binary(name), do: ":#{name}"

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
    "  @doc #{inspect(Enum.join(comments, "\n"), limit: :infinity)}\n"
  end

  defp spec_args([]), do: ""

  defp spec_args(params) do
    params
    |> Enum.map(&TypeMapper.typespec(&1.type))
    |> Enum.map_join("", &", #{&1}")
  end

  defp row_type_source(%TypedQuery{returns: []}), do: ""

  defp row_type_source(%TypedQuery{returns: returns} = query) do
    fields =
      Enum.map_join(returns, ", ", fn column ->
        spec =
          if column.nullable? do
            "#{TypeMapper.typespec(column.type)} | nil"
          else
            TypeMapper.typespec(column.type)
          end

        "required(#{atom_literal(column.name)}) => #{spec}"
      end)

    """
      @type #{row_type_name(query)} :: %{#{fields}}
    """
  end

  defp function_return_typespec(%TypedQuery{returns: []}), do: ":ok"

  defp function_return_typespec(%TypedQuery{} = query) do
    "[#{row_type_name(query)}()]"
  end

  defp generated_function_doc(%TypedQuery{name: name, file: file}) do
    doc = "Runs the `#{name}` query defined in `#{Path.basename(file)}`."
    "  @doc #{inspect(doc, limit: :infinity)}\n"
  end

  # Use inspect/2 so SQL never becomes live Elixir interpolation (`#{}`) in
  # generated modules.
  defp sql_string_literal(content), do: inspect(content, limit: :infinity)

  defp summary_status(0, []), do: :empty
  defp summary_status(_generated_count, []), do: :ok
  defp summary_status(_generated_count, [_ | _]), do: :error
end
