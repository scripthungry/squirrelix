# Types

SquirrElix maps Postgres column and parameter types to Elixir typespecs used in
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

### Dialyzer

Generated modules are written so **adopter Dialyzer** stays useful on call sites:

- Public query `@spec`s and row `@type`s use precise stdlib types (`String.t()`,
  `integer()`, `required/1` maps, `term()` for JSON, and so on).
- Encode helpers carry matching `@spec`s plus guards (`is_integer/1`,
  `is_binary/1`, `is_struct/2`, …) so invalid argument shapes fail early.
- Soft companions document `{:ok, …} | {:error, Exception.t()}`; command soft
  companions use `non_neg_integer()` for affected-row counts.
- Shared private decode helpers intentionally omit broad `@spec`s that would be
  underspecs (`[map()]` / `term()`) relative to per-query row types.

**Recommended Dialyzer flags** for apps that include generated `sql.ex` files:
`:error_handling`, `:underspecs`, `:unknown`, and `:unmatched_returns`.

**Known limitations** (document, do not “fix away”):

| Topic | Expectation |
| --- | --- |
| `:overspecs` / `:specdiffs` | May warn that public row contracts are more precise than success typing of shared `decode_rows` / `Map.new` helpers. That precision is intentional for call sites. |
| `term()` JSON | JSON/JSONB cannot be narrowed further without lying about arrays/scalars. |
| `Exception.t()` | Soft-error contracts use `Exception.t()`; Dialyzer success typing is often a looser exception map. |
| `Postgrex.conn()` | Narrower than Dialyzer’s expanded conn success typing (pid / via / `DBConnection`). |

SquirrElix does **not** ship Dialyxir as a dependency. Run Dialyzer in your app
(see [Phoenix + CI Cookbook](phoenix.md#dialyzer-and-generated-modules)).

### Timestamptz

SquirrElix maps `timestamptz` to `DateTime.t()`. Gleam Squirrel rejects
`timestamptz` with a hint to prefer plain `timestamp`; mapping to `DateTime.t()`
is an intentional Elixir-native choice. Prefer `timestamp` columns when you want
to avoid time-zone conversion surprises at the Postgres connection layer.

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
generated code. SquirrElix does **not** generate Elixir enum modules.

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

Some Postgres types are intentionally unsupported. When inference encounters them,
SquirrElix returns `UnsupportedPostgresType` with the type name and an actionable
hint where one is defined.

### Composite types (policy)

**Decision:** reject with actionable hints — do **not** generate nested row
modules, map composites to `map()`/`term()`, or treat them as opaque strings.

Postgres composite types (`create type ... as (field type, ...)`, `typtype = c`)
are rejected. This matches [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)
and keeps the Elixir-native API limited to stdlib typespecs and flat
`required/1` row maps.

Workarounds when a query would otherwise return a composite:

- Select individual fields: `(location).x`, `(location).y`
- Cast in SQL: `location::json`, `location::jsonb`, or `location::text`
- Reshape the schema into ordinary columns

### Ranges and multiranges

All built-in and user-defined range / multirange types are **rejected**:

| Postgres types | Policy |
| --- | --- |
| `int4range`, `int8range`, `numrange`, `tsrange`, `tstzrange`, `daterange` | Rejected |
| `int4multirange`, `int8multirange`, `nummultirange`, `tsmultirange`, `tstzmultirange`, `datemultirange` | Rejected |
| User-defined `create type ... as range` / multirange | Rejected |

Workarounds:

- Select lower/upper bounds as separate supported columns (for example
  `lower(ages)`, `upper(ages)`).
- Cast the range to `text` or `jsonb` in SQL if you need the literal form.

Postgrex can decode ranges as `Postgrex.Range` at runtime, but SquirrElix does not
generate typed helpers for them — keeping the supported surface aligned with
Gleam Squirrel and Elixir stdlib typespecs.

### Other unsupported built-ins

| Category | Examples | Suggested workaround |
| --- | --- | --- |
| Geometric | `point`, `box`, `circle`, `line`, `lseg`, `path`, `polygon` | Cast to `text`, or select coordinates as floats |
| Network | `inet`, `cidr`, `macaddr`, `macaddr8` | Cast to `text` |
| Interval | `interval` | `extract(epoch from ...)::float8` or cast to `text` |
| Bit strings | `bit`, `varbit` | Cast to `text` |
| Full-text search | `tsvector`, `tsquery` | Cast to `text`, or return ranking/boolean scalars |
| Money | `money` | Prefer `numeric` |
| XML | `xml` | Prefer `text` or `jsonb` |
| OID family | `oid`, `xid`, `tid`, `pg_lsn` | Cast to `text` |
| hstore | `hstore` | Prefer `jsonb` |
| Time with time zone | `timetz` | Prefer `time` |


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

| Aspect | Gleam Squirrel | SquirrElix |
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
- [Phoenix + CI Cookbook](phoenix.md) — Phoenix Mix and CI workflow
