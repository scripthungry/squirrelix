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

  alias Squirrelix.Codegen.Runtime
  alias Squirrelix.Discover
  alias Squirrelix.Output
  alias Squirrelix.Parameter
  alias Squirrelix.Project
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypeMapper

  require Logger

  @spec generate_module(module(), [TypedQuery.t()], keyword()) :: String.t()
  def generate_module(module, queries, opts \\ []) when is_atom(module) and is_list(queries) do
    version = Keyword.fetch!(opts, :version)
    runner = Keyword.get(opts, :runner, :postgrex)
    postgrex_module = Keyword.get(opts, :postgrex, Postgrex)
    # Do not hard-require ecto_sql in this library; adopters supply it at runtime.
    ecto_sql_module = Keyword.get(opts, :ecto_sql, Module.concat([Ecto, Adapters, SQL]))

    sorted_queries = Enum.sort_by(queries, & &1.file)
    exec = execution_context(runner, postgrex_module, ecto_sql_module)

    # Scaffold only: embeds the generated `@moduledoc` and splices query/helper
    # source. Per-query names stay textual so codegen does not create Mix VM atoms.
    # Runtime helpers are quoted in `Squirrelix.Codegen.Runtime`.
    source = """
    defmodule #{inspect(module)} do
      @moduledoc \"\"\"
      This module contains generated query functions.

      > This module was generated automatically using Squirrelix #{version}.

      Runtime row decoding uses `column_spec/0` tuples `{name, type, nullable?}`
      where `type` is an atom such as `:string` or a list wrapper such as
      `{:list, :integer}`.

      #{moduledoc_execution(exec)}

      Public `@spec`s are Dialyzer-oriented for call sites under typical flags
      (`:underspecs`, `:error_handling`, `:unknown`, `:unmatched_returns`). Enabling
      Dialyzer `:overspecs` / `:specdiffs` may warn that row contracts are more
      precise than success typing of shared decode helpers — that is intentional.
      \"\"\"

      @type elixir_type :: atom() | {:list, elixir_type()}
      @type column_spec :: {atom(), elixir_type(), boolean()}

    #{sorted_queries |> function_sources(exec) |> join_function_sources()}#{Runtime.section(queries)}
    end
    """

    source
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp execution_context(:postgrex, postgrex_module, _ecto_sql_module) do
    %{
      runner: :postgrex,
      first_arg: "conn",
      first_arg_type: "Postgrex.conn()",
      query_bang: fn sql, params ->
        "conn\n    |> #{inspect(postgrex_module)}.query!(#{sql}, #{params})"
      end,
      query_soft: fn sql, params ->
        "#{inspect(postgrex_module)}.query(conn, #{sql}, #{params})"
      end
    }
  end

  defp execution_context(:ecto, _postgrex_module, ecto_sql_module) do
    %{
      runner: :ecto,
      first_arg: "repo",
      first_arg_type: "module()",
      query_bang: fn sql, params ->
        "repo\n    |> #{inspect(ecto_sql_module)}.query!(#{sql}, #{params})"
      end,
      query_soft: fn sql, params ->
        "#{inspect(ecto_sql_module)}.query(repo, #{sql}, #{params})"
      end
    }
  end

  defp execution_context(other, _postgrex_module, _ecto_sql_module) do
    raise ArgumentError,
          "unknown codegen runner #{inspect(other)}; expected :postgrex or :ecto"
  end

  defp moduledoc_execution(%{runner: :postgrex}) do
    """
    Each query has a raising function (via `Postgrex.query!/3`) and an additive
    soft companion named `<name>_ok/arity` (via `Postgrex.query/3`) that returns
    `{:ok, result} | {:error, Exception.t()}`. Soft command companions return
    `{:ok, num_rows}` where `num_rows` is the affected-row count.
    """
    |> String.trim()
  end

  defp moduledoc_execution(%{runner: :ecto}) do
    """
    Generated with the optional Ecto runner: the first argument is an Ecto Repo
    module. Raising functions call `Ecto.Adapters.SQL.query!/3`; soft companions
    named `<name>_ok/arity` call `Ecto.Adapters.SQL.query/3` and return
    `{:ok, result} | {:error, Exception.t()}`. Soft command companions return
    `{:ok, num_rows}` where `num_rows` is the affected-row count. This uses Repo
    checkout / transactions / Sandbox — it is not schema or changeset integration.
    """
    |> String.trim()
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
        output_file = Discover.directory_to_output_file(sql_directory)
        # generate_module/3 already runs Code.format_string!/1.
        Output.prepare_write(output_file, content, format: false)

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
        output_file = Discover.directory_to_output_file(sql_directory)

        Output.check_file(output_file, content)

      {:error, :invalid_sql_directory} ->
        {:error, :invalid_sql_directory}
    end
  end

  @spec summarize_write_outcomes([{Path.t(), :ok | {:error, term()}, non_neg_integer()}]) ::
          Squirrelix.CodegenSummary.t()
  def summarize_write_outcomes(outcomes) when is_list(outcomes) do
    {generated_count, errors} = reduce_outcomes(outcomes)

    %Squirrelix.CodegenSummary{
      generated_count: generated_count,
      errors: errors,
      status: summary_status(generated_count, errors)
    }
  end

  @spec summarize_check_outcomes([{Path.t(), :ok | {:error, term()}, non_neg_integer()}]) ::
          Squirrelix.CodegenCheckSummary.t()
  def summarize_check_outcomes(outcomes) when is_list(outcomes) do
    {checked_count, errors} = reduce_outcomes(outcomes)

    %Squirrelix.CodegenCheckSummary{
      checked_count: checked_count,
      errors: errors,
      status: summary_status(checked_count, errors)
    }
  end

  defp reduce_outcomes(outcomes) do
    {count, errors} =
      Enum.reduce(outcomes, {0, []}, fn
        {_directory, :ok, query_count}, {count, errors} ->
          {count + query_count, errors}

        {directory, {:error, error}, _query_count}, {count, errors} ->
          {count, [{directory, error} | errors]}
      end)

    {count, Enum.reverse(errors)}
  end

  defp function_sources(queries, exec) do
    taken_names = MapSet.new(queries, & &1.name)
    _ = validate_row_type_names!(queries)

    queries
    |> Enum.reduce({[], taken_names}, fn query, {sources, claimed} ->
      {source, claimed} = function_source(query, exec, claimed)
      {[source | sources], claimed}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp function_source(%TypedQuery{} = query, exec, claimed_names) do
    raising = raising_function_source(query, exec)

    case soft_companion_name(query.name, claimed_names) do
      {:ok, soft_name} ->
        source = raising <> "\n\n" <> soft_function_source(query, exec, soft_name)
        {source, MapSet.put(claimed_names, soft_name)}

      :skipped ->
        {raising, claimed_names}
    end
  end

  defp raising_function_source(%TypedQuery{} = query, exec) do
    args = TypedQuery.resolve_parameter_names(query.params)
    all_args = [exec.first_arg | args]
    encoded_params = encode_params_call(args, query.params)
    sql = sql_string_literal(query.content)

    [
      doc_source(query),
      row_type_source(query),
      "  @spec #{query.name}(#{exec.first_arg_type}#{spec_args(query.params)}) :: #{function_return_typespec(query)}\n",
      "  def #{query.name}(#{Enum.join(all_args, ", ")}) do\n",
      "    #{exec.query_bang.(sql, encoded_params)}\n",
      "    |> #{decode_call(query.returns)}\n",
      "  end\n"
    ]
    |> Enum.join()
  end

  defp soft_function_source(%TypedQuery{} = query, exec, soft_name) do
    args = TypedQuery.resolve_parameter_names(query.params)
    all_args = [exec.first_arg | args]
    encoded_params = encode_params_call(args, query.params)
    arity = length(all_args)
    sql = sql_string_literal(query.content)

    [
      soft_doc_source(query, arity),
      "  @spec #{soft_name}(#{exec.first_arg_type}#{spec_args(query.params)}) :: #{soft_function_return_typespec(query)}\n",
      "  def #{soft_name}(#{Enum.join(all_args, ", ")}) do\n",
      "    case #{exec.query_soft.(sql, encoded_params)} do\n",
      "      {:ok, result} -> {:ok, result |> #{soft_decode_call(query.returns)}}\n",
      "      {:error, reason} -> {:error, reason}\n",
      "    end\n",
      "  end\n"
    ]
    |> Enum.join()
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

  defp doc_source(
         %TypedQuery{comment: [], returns: [], params: [_, _, _, _, _, _, _, _ | _] = _params} =
           query
       ) do
    generated_function_doc(query)
  end

  defp doc_source(%TypedQuery{comment: []}), do: ""

  defp doc_source(%TypedQuery{comment: comments}) do
    "  @doc #{inspect(Enum.join(comments, "\n"), limit: :infinity)}\n"
  end

  defp spec_args([]), do: ""

  defp spec_args(params) do
    Enum.map_join(params, fn param ->
      ", #{TypeMapper.typespec(param.type)}"
    end)
  end

  defp row_type_source(%TypedQuery{returns: []}), do: ""

  defp row_type_source(%TypedQuery{returns: returns} = query) do
    columns = Enum.map(returns, &{&1.name, &1.type, &1.nullable?})
    "  @type #{row_type_name(query)} :: #{TypeMapper.row_typespec(columns)}\n"
  end

  # Named row types (`find_user_row()`) rather than inlining `TypeMapper.return_typespec/1`
  # so generated modules keep stable, Dialyzer-friendly aliases per query.
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
