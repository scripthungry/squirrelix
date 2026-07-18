defmodule Squirrelixir.Project do
  @moduledoc """
  Helpers for locating and reading an Elixir project.
  """

  @spec root(Path.t()) :: {:ok, Path.t()} | :error
  def root(start_path \\ File.cwd!()) when is_binary(start_path) do
    start_path
    |> Path.expand()
    |> do_root()
  end

  @spec app(Path.t()) :: {:ok, atom()} | :error
  def app(root) when is_binary(root) do
    with {:ok, content} <- File.read(Path.join(root, "mix.exs")),
         {:ok, ast} <- Code.string_to_quoted(content),
         {:ok, app} <- extract_app(ast) do
      {:ok, app}
    else
      _ -> :error
    end
  end

  @spec source_roots(Path.t()) :: [Path.t()]
  def source_roots(root) when is_binary(root) do
    [
      Path.join(root, "lib"),
      Path.join(root, "test"),
      Path.join(root, "dev")
    ]
  end

  @spec module_for_sql_directory(Path.t(), Path.t()) :: {:ok, module()} | :error
  def module_for_sql_directory(root, sql_directory)
      when is_binary(root) and is_binary(sql_directory) do
    with {:ok, app} <- app(root),
         {:ok, relative_segments} <- relative_sql_segments(root, sql_directory) do
      module_parts = [app_module_part(app) | Enum.map(relative_segments, &Macro.camelize/1)]
      {:ok, Module.concat(module_parts ++ ["SQL"])}
    end
  end

  defp do_root(path) do
    cond do
      File.regular?(Path.join(path, "mix.exs")) ->
        {:ok, path}

      Path.dirname(path) == path ->
        :error

      true ->
        path
        |> Path.dirname()
        |> do_root()
    end
  end

  defp extract_app(ast) do
    {_ast, app} =
      Macro.prewalk(ast, nil, fn
        node, nil when is_list(node) ->
          case Keyword.keyword?(node) && Keyword.fetch(node, :app) do
            {:ok, app} when is_atom(app) -> {node, app}
            _ -> {node, nil}
          end

        node, found ->
          {node, found}
      end)

    case app do
      nil -> :error
      app when is_atom(app) -> {:ok, app}
    end
  end

  defp relative_sql_segments(root, sql_directory) do
    root = Path.expand(root)
    sql_directory = Path.expand(sql_directory)

    source_roots(root)
    |> Enum.find_value(:error, fn source_root ->
      source_root = Path.expand(source_root)
      relative_path = Path.relative_to(sql_directory, source_root)

      with true <- Path.basename(sql_directory) == "sql",
           false <- Path.type(relative_path) == :absolute do
        segments = relative_path |> Path.dirname() |> Path.split() |> Enum.reject(&(&1 == "."))
        {:ok, segments}
      else
        _ -> false
      end
    end)
  end

  defp app_module_part(app) do
    app
    |> Atom.to_string()
    |> Macro.camelize()
  end
end
