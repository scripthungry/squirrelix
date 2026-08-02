# Minimal performance smoke suite for SquirrElix.
#
# Run: mix bench
# Or:  mix run bench/micro.exs
#
# Uses :timer.tc/1 only (no Benchee dependency). Prefer several iterations and
# median wall time so local noise is less misleading. See docs/PERFORMANCE.md.

Mix.ensure_application!(:logger)

alias Squirrelix.SQL
alias Squirrelix.Codegen
alias Squirrelix.Output
alias Squirrelix.TypedQuery
alias Squirrelix.Parameter
alias Squirrelix.Column

defmodule Squirrelix.Bench.Micro do
  @iterations 50

  def run do
    IO.puts("SquirrElix microbench (#{@iterations} iterations, median µs)\n")

    sql = fixture_sql()

    module_source_fn = fn ->
      Codegen.generate_module(Squirrelix.Bench.SQL, typed_queries(), version: "bench")
    end

    # Warm once so format/compile caches are less dominant on the first sample.
    _ = module_source_fn.()
    generated = module_source_fn.()

    write_path = Path.join(System.tmp_dir!(), "squirrelix-microbench-sql.ex")
    File.rm(write_path)
    # Warm prepare_write (codegen path passes format: false).
    _ = Output.prepare_write(write_path, generated, format: false)

    report("SQL.infer_parameter_names/1", fn -> SQL.infer_parameter_names(sql) end)
    report("SQL.single_statement?/1", fn -> SQL.single_statement?(sql) end)
    report("Codegen.generate_module/3 (fixture)", module_source_fn)

    report("Output.prepare_write (format: false)", fn ->
      File.rm(write_path)
      Output.prepare_write(write_path, generated, format: false)
    end)

    report("Output.prepare_write (format: true)", fn ->
      File.rm(write_path)
      Output.prepare_write(write_path, generated, format: true)
    end)

    report("compare_code_snippets/2 (same)", fn ->
      Squirrelix.compare_code_snippets(generated, generated)
    end)

    report("compare_code_snippets/2 (drift)", fn ->
      Squirrelix.compare_code_snippets(generated, generated <> "\n")
    end)

    IO.puts("\nDone. See docs/PERFORMANCE.md for CI policy and baselines.")
  end

  defp report(label, fun) do
    samples =
      for _ <- 1..@iterations do
        {us, _result} = :timer.tc(fun)
        us
      end

    median = samples |> Enum.sort() |> Enum.at(div(@iterations, 2))
    min = Enum.min(samples)
    max = Enum.max(samples)

    IO.puts(
      String.pad_trailing(label, 42) <>
        " median=#{median}µs  min=#{min}µs  max=#{max}µs"
    )
  end

  defp fixture_sql do
    """
    -- Find active users matching filters.
    select
      u.id,
      u.email,
      u.inserted_at
    from users as u
    left join profiles as p on p.user_id = u.id
    where u.id = $1
      and u.email ilike $2
      and u.active = $3
    """
  end

  defp typed_queries do
    [
      %TypedQuery{
        file: "lib/demo/sql/find_user.sql",
        starting_line: 1,
        name: "find_user",
        comment: ["Find a user."],
        content: fixture_sql(),
        params: [
          %Parameter{index: 1, name: "id", type: :integer},
          %Parameter{index: 2, name: "email", type: :string},
          %Parameter{index: 3, name: "active", type: :boolean}
        ],
        returns: [
          %Column{name: "id", type: :integer, nullable?: false},
          %Column{name: "email", type: :string, nullable?: false},
          %Column{name: "inserted_at", type: :utc_datetime, nullable?: false}
        ]
      }
    ]
  end
end

Squirrelix.Bench.Micro.run()
