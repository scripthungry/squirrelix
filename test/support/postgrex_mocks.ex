defmodule PostgrexRowsMock do
  @moduledoc false

  def query!({_module, owner, rows: rows}, sql, params) do
    send(owner, {:query!, sql, params})
    SoftQueryResult.result(columns: ["name"], rows: rows)
  end

  def query({_module, owner, rows: rows}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(SoftQueryResult.result(columns: ["name"], rows: rows))
  end
end

defmodule PostgrexMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})
    SoftQueryResult.result(columns: ["name"], rows: [["Ada"]])
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(SoftQueryResult.result(columns: ["name"], rows: [["Ada"]]))
  end
end

defmodule PostgrexCommandMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})
    SoftQueryResult.result(command: :insert, columns: nil, rows: nil, num_rows: 1)
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})

    SoftQueryResult.ok(
      SoftQueryResult.result(command: :insert, columns: nil, rows: nil, num_rows: 1)
    )
  end
end

defmodule PostgrexQuotedStringMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})
    SoftQueryResult.result(columns: ["result"], rows: [[1]])
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(SoftQueryResult.result(columns: ["result"], rows: [[1]]))
  end
end

defmodule PostgrexEnumMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})
    SoftQueryResult.result(columns: ["mood"], rows: [["happy"]])
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(SoftQueryResult.result(columns: ["mood"], rows: [["happy"]]))
  end
end

defmodule PostgrexSoftErrorMock do
  @moduledoc false

  @spec query!(term(), term(), term()) :: no_return()
  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})
    SoftQueryResult.raise_error("boom")
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.error("boom")
  end
end

defmodule SoftQueryResult do
  @moduledoc false

  @spec result(keyword()) :: Postgrex.Result.t()
  def result(opts \\ []) do
    rows = Keyword.get(opts, :rows)

    num_rows =
      Keyword.get_lazy(opts, :num_rows, fn -> if is_list(rows), do: length(rows), else: 0 end)

    %Postgrex.Result{
      command: Keyword.get(opts, :command, :select),
      columns: Keyword.get(opts, :columns),
      rows: rows,
      num_rows: num_rows,
      connection_id: Keyword.get(opts, :connection_id, 1),
      messages: Keyword.get(opts, :messages, [])
    }
  end

  # Keep the return type a real ok/error union for generated soft companions.
  # Runtime always takes the first list element.
  @spec ok(Postgrex.Result.t()) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  def ok(result) do
    List.first([
      {:ok, result},
      {:error, %Postgrex.Error{message: "unreachable soft mock error"}}
    ])
  end

  @spec error(String.t()) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  def error(message) do
    List.first([
      {:error, %Postgrex.Error{message: message}},
      {:ok, result(columns: [], rows: [], num_rows: 0)}
    ])
  end

  @spec raise_error(String.t()) :: no_return()
  def raise_error(message) do
    raise %Postgrex.Error{message: message}
  end
end
