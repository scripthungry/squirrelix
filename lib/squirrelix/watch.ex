defmodule Squirrelix.Watch do
  @moduledoc false

  alias Squirrelix.Project

  @default_debounce_ms 200

  @doc false
  @spec sql_query_path?(Path.t(), Path.t()) :: boolean()
  def sql_query_path?(path, root) when is_binary(path) and is_binary(root) do
    path = canonicalize(path)
    root = canonicalize(root)

    Path.extname(path) == ".sql" and
      Path.basename(Path.dirname(path)) == "sql" and
      under_source_root?(path, root)
  end

  @doc false
  @spec watchable_dirs(Path.t()) :: [Path.t()]
  def watchable_dirs(root) when is_binary(root) do
    root
    |> Project.source_roots()
    |> Enum.filter(&File.dir?/1)
  end

  @doc false
  @spec watch!(keyword()) :: :ok
  def watch!(opts) when is_list(opts) do
    root = Keyword.fetch!(opts, :root) |> Path.expand()
    dirs = Keyword.get_lazy(opts, :dirs, fn -> watchable_dirs(root) end)
    on_change = Keyword.fetch!(opts, :on_change)
    debounce_ms = Keyword.get(opts, :debounce_ms, @default_debounce_ms)
    after_start = Keyword.get(opts, :after_start)

    case dirs do
      [] ->
        Mix.shell().error(
          "Squirrelix watch: no lib/, test/, or dev/ directories to watch under #{root}."
        )

        :ok

      dirs ->
        filesystem_opts =
          [dirs: dirs]
          |> Keyword.merge(Application.get_env(:squirr_elix, :watch_filesystem_opts, []))

        watcher_pid = start_filesystem!(filesystem_opts)
        FileSystem.subscribe(watcher_pid)

        if is_function(after_start, 1) do
          after_start.(self())
        end

        run_loop(%{
          root: root,
          debounce_ms: debounce_ms,
          watcher_pid: watcher_pid,
          timer: nil,
          on_change: on_change
        })
    end
  end

  defp start_filesystem!(filesystem_opts) do
    case FileSystem.start_link(filesystem_opts) do
      {:ok, pid} ->
        pid

      :ignore ->
        Mix.raise("""
        Could not start the file watcher (FileSystem returned :ignore).

        On Linux, install inotify-tools (e.g. `apt install inotify-tools`).
        See https://github.com/rvoicilas/inotify-tools/wiki
        """)

      {:error, reason} ->
        Mix.raise("""
        Could not start the file watcher.

        Reason: #{format_watch_reason(reason)}
        """)
    end
  end

  @doc false
  @spec run_loop(map()) :: :ok
  def run_loop(state) when is_map(state) do
    receive do
      {:file_event, watcher_pid, {path, _events}} when watcher_pid == state.watcher_pid ->
        state
        |> maybe_schedule(path)
        |> run_loop()

      {:file_event, watcher_pid, :stop} when watcher_pid == state.watcher_pid ->
        Mix.shell().info("Squirrelix watch stopped.")
        :ok

      :squirrelix_watch_regenerate ->
        state.on_change.()
        run_loop(%{state | timer: nil})

      :squirrelix_watch_stop ->
        cancel_timer(state.timer)
        Mix.shell().info("Squirrelix watch stopped.")
        :ok
    end
  end

  defp maybe_schedule(state, path) do
    if sql_query_path?(path, state.root) do
      cancel_timer(state.timer)
      timer = Process.send_after(self(), :squirrelix_watch_regenerate, state.debounce_ms)
      %{state | timer: timer}
    else
      state
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp format_watch_reason(reason) when is_binary(reason), do: reason
  defp format_watch_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_watch_reason(%{__exception__: true} = reason), do: Exception.message(reason)
  defp format_watch_reason(reason), do: inspect(reason)

  defp under_source_root?(path, root) do
    Enum.any?(Project.source_roots(root), fn source_root ->
      source_root = canonicalize(source_root)
      relative = Path.relative_to(path, source_root)
      Path.type(relative) != :absolute
    end)
  end

  # macOS FileSystem backends often report `/private/var/...` while Elixir tmp
  # paths use `/var/...` (symlink). Normalize so prefix checks agree.
  defp canonicalize(path) do
    path = Path.expand(path)
    String.replace_prefix(path, "/private", "")
  end
end
