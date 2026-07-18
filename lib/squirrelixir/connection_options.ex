defmodule Squirrelixir.ConnectionOptions do
  @enforce_keys [:host, :port, :user, :password, :database, :timeout_seconds]
  defstruct [:host, :port, :user, :password, :database, :timeout_seconds]

  @type t :: %__MODULE__{
          host: String.t(),
          port: pos_integer(),
          user: String.t(),
          password: String.t(),
          database: String.t(),
          timeout_seconds: non_neg_integer()
        }
end
