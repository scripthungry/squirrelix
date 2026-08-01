defmodule Squirrelix do
  @moduledoc """
  Elixir-native SQL query code generation for Mix projects.

  SquirrElix discovers `.sql` files under conventional Elixir source roots
  (`lib/`, `test/`, `dev/`), then generates sibling `sql.ex` modules with
  `@spec`-annotated functions that execute through Postgrex.

  ## Supported public API

  Pre-1.0, the **supported** programmatic surface is intentionally small:

    * `generate/3` / `check/3` — primary entry points
    * Mix tasks `mix squirrelix.gen` and `mix squirrelix.check`
    * Return summaries `Squirrelix.CodegenSummary` / `Squirrelix.CodegenCheckSummary`
    * Documented `Squirrelix.Error.*` structs (and `Squirrelix.Error.format/1`)
    * `Squirrelix.Postgres.inferrer/1` and `Squirrelix.Inference.Inferrer`
      (plus `Squirrelix.Query` as the Inferrer callback argument)

  Other modules under `Squirrelix.*` are **internal** (`@moduledoc false`) and
  may change without notice. See [Configuration](configuration.html#supported-public-api)
  for the full inventory.

  ## Guides

    * [Getting Started](getting_started.html) — installation, layout, first query
    * [Writing Queries](writing_queries.html) — one query per file, comments, naming
    * [Types](types.html) — Postgres to Elixir type mapping
    * [Configuration](configuration.html) — inference, metadata, connection, CI

  See also `README.md` for a full overview.

  ## Query sources

  Generation and checking accept a *query source* in one of two forms:

    * A metadata map — keys are query file paths, values are keyword lists with
      `:params` and `:returns`. Load from `squirr_elix.exs` or pass a map to
      `generate/3` and `check/3`.
    * An inferrer — a `(query -> {:ok, keyword()} | {:error, struct()})` function
      or a module implementing `Squirrelix.Inference.Inferrer`. The Mix task
      uses this mode with `--infer` to ask Postgres for column and parameter types.

  Generated code uses stdlib types in `@spec` output: `String.t()` for Postgres
  enums, `term()` for JSON/JSONB columns, `map()` with `required/1` for row
  shapes, and plain maps at runtime rather than Gleam records or custom enum ADTs.
  """

  # Marker written into generated `@moduledoc`. Classification only trusts this
  # near the top of the file so a buried mention cannot spoof overwrite.
  @generated_module_marker "> 🐿️ This module was generated automatically using"
  @generated_module_marker_ascii "> This module was generated automatically using"
  @generated_header_bytes 2_048

  @type metadata :: %{Path.t() => keyword()}
  @type query_source :: metadata() | Squirrelix.Inference.inferrer()

  # Internal: used by safe overwrite / drift detection. Not part of the supported API.
  @doc false
  @spec classify_file_content(String.t()) :: :likely_generated | :empty | :not_generated
  def classify_file_content(content) when is_binary(content) do
    header = binary_prefix(content, @generated_header_bytes)

    likely_generated? =
      String.contains?(header, @generated_module_marker) or
        String.contains?(header, @generated_module_marker_ascii)

    cond do
      likely_generated? -> :likely_generated
      String.trim(content) == "" -> :empty
      true -> :not_generated
    end
  end

  defp binary_prefix(content, max_bytes) when byte_size(content) <= max_bytes, do: content

  defp binary_prefix(content, max_bytes) do
    binary_part(content, 0, max_bytes)
  end

  # Internal: used by drift detection. Not part of the supported API.
  @doc false
  @spec compare_code_snippets(String.t(), String.t()) :: :same | :different
  def compare_code_snippets(actual_code, expected_code)
      when is_binary(actual_code) and is_binary(expected_code) do
    if tokenize(actual_code) == tokenize(expected_code) do
      :same
    else
      :different
    end
  end

  @doc """
  Generates query modules for SQL files discovered under a Mix project root.

  Generation is **project-wide atomic**:

    * If any `sql/` directory has query errors (invalid names, missing metadata,
      inference failures, …), nothing is written — including directories that
      would otherwise succeed.
    * If every directory is query-valid but any prepared write would fail
      (for example `CannotOverwriteFile`), nothing is written.
    * Successful writes use temp files + rename, with rollback if a later rename
      fails mid-pass.

  Fix every error, then re-run.

  ## Options

    * `:version` (required) — generator version string written into file headers
    * `:postgrex` — module passed to generated code (defaults to `Postgrex`)

  Returns a `Squirrelix.CodegenSummary` struct summarizing writes and errors.
  """
  @spec generate(Path.t(), query_source(), keyword()) :: Squirrelix.CodegenSummary.t()
  def generate(root, query_source, opts \\ []) when is_binary(root) and is_list(opts) do
    case typed_query_directories(root, query_source) do
      {:error, error} ->
        Squirrelix.Codegen.summarize_write_outcomes([{root, {:error, error}, 0}])

      directories when is_list(directories) ->
        case directory_query_errors(directories) do
          [] ->
            write_all_or_nothing(root, directories, opts)

          errors ->
            # Gleam squirrel 4.5+ parity: refuse all writes when any query errors exist.
            Squirrelix.Codegen.summarize_write_outcomes(errors)
        end
    end
  end

  @doc """
  Checks that generated query modules are current without writing files.

  Accepts the same `query_source` and options as `generate/3`.
  Fails globally when any directory has query errors or drift — the summary
  status is `:error` and every failing directory is included in `:errors`.

  Returns a `Squirrelix.CodegenCheckSummary` struct.
  """
  @spec check(Path.t(), query_source(), keyword()) :: Squirrelix.CodegenCheckSummary.t()
  def check(root, query_source, opts \\ []) when is_binary(root) and is_list(opts) do
    case typed_query_directories(root, query_source) do
      {:error, error} ->
        Squirrelix.Codegen.summarize_check_outcomes([{root, {:error, error}, 0}])

      directories when is_list(directories) ->
        directories
        |> Enum.map(&check_typed_directory(root, &1, opts))
        |> Squirrelix.Codegen.summarize_check_outcomes()
    end
  end

  @spec tokenize(String.t()) :: [String.t()]
  defp tokenize(code) do
    chars = String.to_charlist(code)

    chars
    |> do_tokenize(:normal, [], [])
    |> Enum.reverse()
  end

  defp do_tokenize([], :normal, current, tokens), do: maybe_push(current, tokens)
  defp do_tokenize([], :line_comment, current, tokens), do: maybe_push(current, tokens)
  defp do_tokenize([], :string, current, tokens), do: maybe_push(current, tokens)

  defp do_tokenize([?/, ?/ | rest], :normal, current, tokens) do
    tokens = maybe_push(current, tokens)
    do_tokenize(rest, :line_comment, [], tokens)
  end

  defp do_tokenize([?# | rest], :normal, current, tokens) do
    tokens = maybe_push(current, tokens)
    do_tokenize(rest, :line_comment, [], tokens)
  end

  defp do_tokenize([char | rest], :line_comment, current, tokens) do
    if char == ?\n do
      do_tokenize(rest, :normal, current, tokens)
    else
      do_tokenize(rest, :line_comment, current, tokens)
    end
  end

  defp do_tokenize([?" | rest], :normal, current, tokens) do
    tokens = maybe_push(current, tokens)
    do_tokenize(rest, :string, [?"], tokens)
  end

  defp do_tokenize([?\\, escaped | rest], :string, current, tokens) do
    do_tokenize(rest, :string, [escaped, ?\\ | current], tokens)
  end

  defp do_tokenize([?" | rest], :string, current, tokens) do
    token = [?" | Enum.reverse(current)]
    do_tokenize(rest, :normal, [], [List.to_string(token) | tokens])
  end

  defp do_tokenize([char | rest], :string, current, tokens) do
    do_tokenize(rest, :string, [char | current], tokens)
  end

  defp do_tokenize([char | rest], :normal, current, tokens) when char in [32, 9, 10, 13] do
    tokens = maybe_push(current, tokens)
    do_tokenize(rest, :normal, [], tokens)
  end

  defp do_tokenize([char | rest], :normal, current, tokens) do
    char_string = <<char::utf8>>

    if identifier_char?(char) do
      do_tokenize(rest, :normal, [char | current], tokens)
    else
      tokens = maybe_push(current, tokens)
      do_tokenize(rest, :normal, [], [char_string | tokens])
    end
  end

  defp maybe_push([], tokens), do: tokens

  defp maybe_push(current, tokens) do
    [current |> Enum.reverse() |> List.to_string() | tokens]
  end

  defp identifier_char?(char) do
    (char >= ?a and char <= ?z) or
      (char >= ?A and char <= ?Z) or
      (char >= ?0 and char <= ?9) or
      char in [?_]
  end

  defp typed_query_directories(root, metadata) when is_map(metadata) do
    case Squirrelix.Discover.query_directories(root) do
      {:ok, directories} ->
        directories
        |> Enum.map(&Squirrelix.TypedQueryDirectory.from_query_directory(&1, metadata))
        |> Enum.sort_by(& &1.directory)

      {:error, _} = error ->
        error
    end
  end

  defp typed_query_directories(root, inferrer)
       when is_function(inferrer, 1) or is_atom(inferrer) do
    case Squirrelix.Discover.query_directories(root) do
      {:ok, directories} ->
        Squirrelix.Inference.from_query_directories(directories, inferrer)

      {:error, _} = error ->
        error
    end
  end

  defp directory_query_errors(directories) do
    directories
    |> Enum.filter(fn %Squirrelix.TypedQueryDirectory{errors: errors} -> errors != [] end)
    |> Enum.map(fn %Squirrelix.TypedQueryDirectory{} = directory ->
      {directory.directory, {:error, directory.errors}, length(directory.queries)}
    end)
  end

  defp write_all_or_nothing(root, directories, opts) do
    prepared =
      directories
      |> Enum.sort_by(& &1.directory)
      |> Enum.map(&prepare_typed_directory(root, &1, opts))

    case Enum.reject(prepared, fn {_dir, result, _count} -> match?({:ok, _}, result) end) do
      [] ->
        commit_prepared_writes(prepared)

      errors ->
        errors
        |> Enum.map(fn {dir, {:error, reason}, count} -> {dir, {:error, reason}, count} end)
        |> Squirrelix.Codegen.summarize_write_outcomes()
    end
  end

  defp prepare_typed_directory(root, %Squirrelix.TypedQueryDirectory{} = directory, opts) do
    result =
      Squirrelix.Codegen.prepare_directory(
        root,
        directory.directory,
        directory.queries,
        opts
      )

    {directory.directory, result, length(directory.queries)}
  end

  defp commit_prepared_writes(prepared) do
    writes = Enum.map(prepared, fn {_dir, {:ok, write}, _count} -> write end)

    case Squirrelix.Output.commit_writes(writes) do
      :ok ->
        prepared
        |> Enum.map(fn {dir, {:ok, _}, count} -> {dir, :ok, count} end)
        |> Squirrelix.Codegen.summarize_write_outcomes()

      {:error, error} ->
        Squirrelix.Codegen.summarize_write_outcomes([{error.file, {:error, error}, 0}])
    end
  end

  defp check_typed_directory(
         root,
         %Squirrelix.TypedQueryDirectory{errors: []} = directory,
         opts
       ) do
    outcome =
      Squirrelix.Codegen.check_directory(root, directory.directory, directory.queries, opts)

    {directory.directory, outcome, length(directory.queries)}
  end

  defp check_typed_directory(_root, %Squirrelix.TypedQueryDirectory{} = directory, _opts) do
    {directory.directory, {:error, directory.errors}, length(directory.queries)}
  end
end
