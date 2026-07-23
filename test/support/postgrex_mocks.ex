defmodule PostgrexRowsMock do
  @moduledoc false

  def query!({_module, owner, rows: rows}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["name"], rows: rows}
  end
end

defmodule PostgrexMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["name"], rows: [["Ada"]]}
  end
end

defmodule PostgrexCommandMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{command: :insert, columns: nil, rows: nil, num_rows: 1}
  end
end

defmodule PostgrexQuotedStringMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["result"], rows: [[1]]}
  end
end

defmodule PostgrexEnumMock do
  @moduledoc false

  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})

    %Postgrex.Result{columns: ["mood"], rows: [["happy"]]}
  end
end
