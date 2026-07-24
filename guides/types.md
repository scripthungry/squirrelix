# Types

Squirrelix maps Postgres column and parameter types to Elixir typespecs used in
generated `@spec`s and row `@type` definitions. This guide describes the supported
mappings and intentional differences from Gleam Squirrel.

## How types are used

Types appear in two places:

1. **Generated `@spec`s and `@type` definitions** — static documentation and Dialyzer
   hints for your query functions and row maps.
2. **Runtime encode/decode** — generated helper functions convert Elixir values to
   Postgrex parameters and Postgrex result values to plain Elixir terms.

Row shapes use `map/0` with `required/1` keys:

```elixir
@type find_user_row :: %{
  required(:name) => String.t(),
  required(:age) => integer()
}

@spec find_user(Postgrex.conn(), integer()) :: [find_user_row()]
```

Nullable columns add `| nil` to the value type:

```elixir
@type find_user_row :: %{
  required(:bio) => String.t() | nil
}
```

## Supported Postgres types

| Postgres type | `@spec` / row type | Runtime encode/decode |
| --- | --- | --- |
| `bool` | `boolean()` | `true` / `false` |
| `text`, `char`, `bpchar`, `varchar`, `citext`, `name` | `String.t()` | UTF-8 strings |
| `float4`, `float8` | `float()` | floats |
| `numeric` | `Decimal.t()` | `Decimal` structs |
| `int2`, `int4`, `int8` | `integer()` | integers |
| `json`, `jsonb` | `term()` | maps, lists, or primitives |
| `uuid` | `String.t()` | UUID strings |
| `bytea` | `binary()` | binaries |
| `date` | `Date.t()` | `Date` structs |
| `time` | `Time.t()` | `Time` structs |
| `timestamp` | `NaiveDateTime.t()` | `NaiveDateTime` structs |
| `timestamptz` | `DateTime.t()` | `DateTime` structs |
| `<type>[]` | `[inner_type]` | lists |
| user-defined enum | `String.t()` | enum label strings |
| user-defined domain | base type | resolved to base type |

### JSON and JSONB

JSON columns use `term()` in `@spec`s because JSON values are not always objects.
Postgrex may return maps, lists, strings, numbers, booleans, or `nil` depending on
the stored payload.

```elixir
@type payload_row :: %{required(:payload) => term()}
```

At runtime, JSON values pass through as decoded Elixir terms.

### UUID

UUID columns use `String.t()` rather than a custom opaque type. Values are standard
UUID strings such as `"550e8400-e29b-41d4-a716-446655440000"`.

### Timestamptz

Squirrelix maps `timestamptz` to `DateTime.t()`. When inference encounters
`timestamptz`, Squirrelix may emit a hint recommending plain `timestamp` columns
to avoid time-zone conversion surprises.

Gleam Squirrel maps `timestamptz` differently; this is an intentional Elixir-native
choice.

### Arrays

Postgres array types map to Elixir lists recursively:

| Postgres | Elixir |
| --- | --- |
| `integer[]` | `[integer()]` |
| `text[]` | `[String.t()]` |
| `uuid[]` | `[String.t()]` |

Nullable elements inside arrays follow Postgrex decoding behaviour.

## Postgres enums

User-defined Postgres enums (`create type ... as enum`) map to `String.t()` in
generated code. Squirrelix does **not** generate Elixir enum modules.

Given:

```sql
create type squirrel_colour as enum ('light_brown', 'grey', 'red');
```

A column typed `squirrel_colour` appears as `String.t()` in `@spec`s and decodes to
`"light_brown"`, `"grey"`, or `"red"`.

This differs from Gleam Squirrel, which generates custom enum types. The Elixir
approach keeps generated modules simple and avoids naming conflicts when enum labels
do not map cleanly to Elixir identifiers.

Enums with no variants are rejected with a structured error.

## Domains

User-defined domains (`create domain ... as ...`) are resolved to their base Postgres
type for both inference and code generation.

## Unsupported types

Some Postgres types are not yet supported. When inference encounters them,
Squirrelix returns `UnsupportedPostgresType` with the type name and, when
available, a hint.

Currently rejected types include composite types and some built-ins such as `point`.
Check error output for actionable suggestions.

## Metadata type atoms

When using a metadata file instead of `--infer`, use these atoms for `:params` and
column `:type` values:

| Atom | Meaning |
| --- | --- |
| `:boolean` | `bool` |
| `:string` | text-like types and enums |
| `:integer` | `int2`, `int4`, `int8` |
| `:float` | `float4`, `float8` |
| `:decimal` | `numeric` |
| `:binary` | `bytea` |
| `:uuid` | `uuid` |
| `:date` | `date` |
| `:time` | `time` |
| `:naive_datetime` | `timestamp` |
| `:utc_datetime` | `timestamptz` |
| `:map` | `json`, `jsonb` |
| `{:list, inner}` | Postgres arrays |

Example metadata entry:

```elixir
"lib/my_app/sql/find_user.sql" => [
  params: [:integer, :string],
  returns: [
    %{name: "id", type: :integer, nullable?: false},
    %{name: "tags", type: {:list, :string}, nullable?: false},
    %{name: "metadata", type: :map, nullable?: true}
  ]
]
```

## Differences from Gleam Squirrel

| Aspect | Gleam Squirrel | Squirrelix |
| --- | --- | --- |
| Row shape | Custom record type | `map()` with `required/1` |
| Postgres enums | Generated enum ADT | `String.t()` |
| UUID | `uuid.Uuid` opaque type | `String.t()` |
| JSON decode | `String` (Gleam) | `term()` |
| `timestamptz` | Hint to use `timestamp` | `DateTime.t()` |
| Database driver | `pog` | `Postgrex` |

See [NOTICE](../NOTICE) for upstream attribution.

## Next steps

- [Writing Queries](writing_queries.md) — nullable parameters and naming
- [Configuration](configuration.md) — inference vs metadata mode
