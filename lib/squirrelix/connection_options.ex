defmodule Squirrelix.ConnectionOptions do
  @moduledoc false

  @enforce_keys [:host, :port, :user, :password, :database, :timeout_seconds]
  defstruct [:host, :port, :user, :password, :database, :timeout_seconds, ssl: false]

  @type ssl :: boolean() | keyword() | nil

  @type t :: %__MODULE__{
          host: String.t(),
          port: pos_integer(),
          user: String.t(),
          password: String.t(),
          database: String.t(),
          timeout_seconds: non_neg_integer(),
          ssl: ssl()
        }
end
