defmodule PostgrexRowsMock do
  @moduledoc false

  def query!({_module, owner, rows: rows}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["name"], rows: rows}
  end

  def query({_module, owner, rows: rows}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(%Postgrex.Result{columns: ["name"], rows: rows})
  end
end

defmodule PostgrexMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["name"], rows: [["Ada"]]}
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(%Postgrex.Result{columns: ["name"], rows: [["Ada"]]})
  end
end

defmodule PostgrexCommandMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{command: :insert, columns: nil, rows: nil, num_rows: 1}
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(%Postgrex.Result{command: :insert, columns: nil, rows: nil, num_rows: 1})
  end
end

defmodule PostgrexQuotedStringMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["result"], rows: [[1]]}
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(%Postgrex.Result{columns: ["result"], rows: [[1]]})
  end
end

defmodule PostgrexEnumMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["mood"], rows: [["happy"]]}
  end

  def query({_module, owner}, sql, params) do
    send(owner, {:query, sql, params})
    SoftQueryResult.ok(%Postgrex.Result{columns: ["mood"], rows: [["happy"]]})
  end
end

defmodule PostgrexSoftErrorMock do
  @moduledoc false

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
      {:ok, %Postgrex.Result{columns: [], rows: [], num_rows: 0}}
    ])
  end

  @spec raise_error(String.t()) :: no_return()
  def raise_error(message) do
    raise %Postgrex.Error{message: message}
  end
end
