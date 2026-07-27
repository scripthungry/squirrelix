defmodule Squirrelix.ConnectionOptions do
  @moduledoc """
  PostgreSQL connection settings for Squirrelix.

  Squirrelix uses a plain Elixir struct — not a Gleam-style opaque record.
  Fields are regular struct keys you can pattern match on or convert to a
  Postgrex/DBConnection keyword list when needed.

  ## SSL

  The `:ssl` field is passed through to Postgrex as the `:ssl` start option:

  - `false` — no TLS (default)
  - `true` — TLS with Postgrex secure defaults (peer + hostname verification)
  - keyword list — TLS with custom `:ssl` options (for example
    `[verify: :verify_none]` for `sslmode=require`)
  - `nil` — unset (used when a URL omits SSL params so env/`PGSSLMODE` can apply)
  """

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
