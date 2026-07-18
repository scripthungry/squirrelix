defmodule Squirrelixir.Codegen do
  @moduledoc """
  Generates Elixir modules for typed SQL queries.
  """

  alias Squirrelixir.Parameter
  alias Squirrelixir.Output
  alias Squirrelixir.Project
  alias Squirrelixir.TypedQuery
  alias Squirrelixir.TypedQueryDirectory

  @spec generate_module(module(), [TypedQuery.t()], keyword()) :: String.t()
  def generate_module(module, queries, opts \\ []) when is_atom(module) and is_list(queries) do
    version = Keyword.fetch!(opts, :version)

    source = """
    defmodule #{inspect(module)} do
      @moduledoc \"\"\"
      This module contains generated query functions.

      > This module was generated automatically using Squirrelixir #{version}.
      \"\"\"

    #{queries |> Enum.sort_by(& &1.file) |> Enum.map_join("\n\n", &function_source/1)}
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
    with {:ok, module} <- Project.module_for_sql_directory(root, sql_directory) do
      content = generate_module(module, queries, opts)
      output_file = sql_directory |> Path.dirname() |> Path.join("sql.ex")

      Output.safe_write(output_file, content)
    else
      :error -> {:error, :invalid_sql_directory}
    end
  end

  @spec write_directories(Path.t(), [TypedQueryDirectory.t()], keyword()) :: [
          {Path.t(), :ok | {:error, :invalid_sql_directory | struct()}}
        ]
  def write_directories(root, directories, opts \\ [])
      when is_binary(root) and is_list(directories) and is_list(opts) do
    directories
    |> Enum.sort_by(& &1.directory)
    |> Enum.map(fn %TypedQueryDirectory{directory: directory, queries: queries} ->
      {directory, write_directory(root, directory, queries, opts)}
    end)
  end

  defp function_source(%TypedQuery{} = query) do
    args = argument_names(query.params)
    all_args = ["connection" | args]
    params = Enum.join(args, ", ")

    """
      #{doc_source(query)}
      @spec #{query.name}(Postgrex.conn()#{spec_args(query.params)}) :: Postgrex.Result.t()
      def #{query.name}(#{Enum.join(all_args, ", ")}) do
        Postgrex.query!(connection, #{inspect(query.content)}, [#{params}])
      end
    """
  end

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

  defp type_spec(:integer), do: "integer()"
  defp type_spec(:string), do: "String.t()"
  defp type_spec(:boolean), do: "boolean()"
  defp type_spec(:float), do: "float()"
  defp type_spec(:binary), do: "binary()"
  defp type_spec(:map), do: "map()"
  defp type_spec({:list, type}), do: "[#{type_spec(type)}]"
  defp type_spec(_type), do: "term()"
end
