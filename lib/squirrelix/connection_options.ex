defmodule Squirrelix.ConnectionOptions do
  @moduledoc """
  PostgreSQL connection settings for Squirrelix.

  Squirrelix uses a plain Elixir struct — not a Gleam-style opaque record.
  Fields are regular struct keys you can pattern match on or convert to a
  Postgrex/DBConnection keyword list when needed.
  """

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
