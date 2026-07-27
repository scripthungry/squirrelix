# Writing Queries

Squirrelix follows a small set of conventions inherited from
[Gleam Squirrel](https://github.com/giacomocavalieri/squirrel). This guide covers
where to put queries, how files map to functions, and practical tips for edge cases.

## One query per file

Each `*.sql` file **must contain exactly one SQL statement.** Squirrelix turns the
file into a single Elixir function with the same name as the file (without the
`.sql` extension).

```txt
lib/my_app/accounts/sql/
├── find_user.sql       → find_user/2
├── list_users.sql      → list_users/1
└── update_email.sql    → update_email/3
```

Do not put multiple queries in one file. If you need related variants, use separate
files — for example `set_recipe_author.sql` and `remove_recipe_author.sql`.

## Directory layout

Place queries in a directory named `sql/` anywhere under `lib/`, `test/`, or `dev/`:

```txt
{lib,test,dev}/**/sql/*.sql
```

All queries in the same `sql/` directory are grouped into one generated `sql.ex`
module next to that directory.

> **Example.** Files in `lib/my_app/accounts/sql/` generate `MyApp.Accounts.SQL` at
> `lib/my_app/accounts/sql.ex`.

## Comments become documentation

Leading SQL comments are extracted and become `@doc` strings on the generated
function:

```sql
-- Find all active users ordered by name.
select
  id,
  name
from
  users
where
  active = true
order by
  name
```

Generates:

```elixir
@doc """
Find all active users ordered by name.
"""
@spec list_active_users(Postgrex.conn()) :: [list_active_users_row()]
def list_active_users(conn) do
```

Only leading `-- line comments` become the generated function `@doc`. Block comments
(`/* ... */`) are ignored for docs, but both line and block comments (including nested
blocks) are stripped when inferring parameter names from comparisons, `INSERT` column
lists, and `SET (columns) = (...)` bindings. Comments inside string literals are
ignored for parameter-name inference as well.

## File and function naming

The `.sql` filename must be a valid Elixir function name in `snake_case`:

| Valid | Invalid |
| --- | --- |
| `find_user.sql` | `FindUser.sql` |
| `list_active_users.sql` | `find user.sql` |
| `delete_by_id.sql` | `1st_query.sql` |

If a filename cannot become a valid function name, Squirrelix reports a
`QueryFileHasInvalidName` error and may suggest a corrected name.

Result column names must also be valid Elixir map keys. If a column name from Postgres
is invalid, Squirrelix reports `QueryHasInvalidColumn` with a suggested alias.

Use `as` in your `select` list when needed:

```sql
select
  u.created_at as user_created_at
from
  users u
```

## Parameter naming

Squirrelix infers Elixir argument names from how `$1`, `$2`, ... appear in your
query.

**Comparisons** (including `UPDATE ... SET col = $n` and `DELETE`/`UPDATE`/`SELECT`
`WHERE` clauses):

```sql
update users
set
  email = $1
where
  id = $2
```

Generates `update_email(conn, email, id)`.

Also names parameters beside `<>`, `!=`, `<`, `>`, `<=`, `>=`, and `LIKE` /
`ILIKE` (including `NOT LIKE` / `NOT ILIKE`):

```sql
select name from users
where id > $1
  and name ilike $2
```

Generates `list_users(conn, id, name)`.

**`INSERT` column lists with `VALUES`:**

```sql
insert into users (name, email)
values ($1, $2)
```

Generates `insert_user(conn, name, email)`.

Placeholders are paired with columns by position. Literals, `DEFAULT`, and other
non-placeholder values are skipped for naming. Multi-row `VALUES` reuse the same
column list for each row.

**`SET (columns) = (...)` lists** (including `ON CONFLICT ... DO UPDATE SET`):

```sql
update users
set (name, email) = ($1, $2)
where id = $3
```

Generates `patch_user(conn, name, email, id)`.

`ROW($1, $2)` on the right-hand side is supported the same way.

Inference ignores string literals and comments. When comparison/equality naming
and a column-list shape (`INSERT` or `SET (...)`) both name the same parameter
index, the comparison/equality name wins. Names that would shadow the `conn`
parameter or other reserved names are deconflicted.

When the same parameter index appears more than once, Squirrelix renames arguments
to keep generated code valid.

### Naming inventory (in scope vs leftovers)

| Shape | Named? |
| --- | --- |
| `col = $n` / `$n = col` (incl. `UPDATE ... SET`) | Yes |
| `col` with `<>`, `!=`, `<`, `>`, `<=`, `>=` | Yes |
| `col LIKE` / `ILIKE` / `NOT LIKE` / `NOT ILIKE $n` | Yes |
| `INSERT (cols) VALUES (...)` placeholders | Yes |
| `SET (cols) = ($n…)` / `ROW($n…)` (incl. `ON CONFLICT DO UPDATE`) | Yes |
| `INSERT ... VALUES` without a column list | No → `arg_n` |
| `INSERT ... SELECT $n` | No → `arg_n` |
| `IN ($n…)`, `BETWEEN $n AND $m`, `= ANY($n)` | No → `arg_n` |
| Function-wrapped columns (`lower(email) = $n`) | No → `arg_n` |
| JSON operators (`data->>'k' = $n`) | No → `arg_n` |
| Bare `$n IS NULL` | No → `arg_n` |

Parameters that cannot be named from SQL fall back to `arg_1`, `arg_2`, and so on.

## Sort order in generated modules

Generated functions are sorted by **source file path** (alphabetically), not by
function name. This matches Gleam Squirrel's reproducibility guarantees when filenames
and function names differ.

## Nullable result columns

Squirrelix infers nullability for returned columns from Postgres metadata,
including outer join columns and foreign-key-derived cases. Nullable columns appear
in `@spec`s and row types with `| nil`:

```elixir
@type find_user_row :: %{
  required(:name) => String.t(),
  required(:bio) => String.t() | nil
}
```

At runtime, `nil` values decode to Elixir `nil`.

Inference also covers:

- **Schema-qualified tables** — `schema.table` columns use catalog nullability for that
  schema (including tables outside `search_path`).
- **Scalar subqueries in the select list** — treated as nullable (they can return no
  row). This is intentionally stricter than Gleam Squirrel, which treats
  non-table columns as non-nullable.
- **Expression-derived columns** — `id + 1`, `upper(name)`, `coalesce(...)`, and similar
  are treated as non-nullable, matching Gleam Squirrel's `table_oid = 0` behaviour.
  Override with a `"name?"` / `"name!"` column alias when needed.

## Nullable query parameters

Postgres does not expose nullability information for query **parameters**. Squirrelix
therefore cannot infer that `$1` should accept `nil` when updating a nullable column.

Consider this schema:

```sql
create table if not exists recipe (
  id int primary key,
  title text not null,
  author uuid,        -- might be missing
  description text    -- might be missing
);
```

And this query:

```sql
-- update_recipe_author.sql
update recipe
set author = $1
where id = $2;
```

The generated function will type `$1` as a non-nullable UUID string, even though
the column accepts `null`.

### Recommended workarounds

1. **Split into separate queries** when there are few nullable arguments:

   ```sql
   -- set_recipe_author.sql
   update recipe set author = $1 where id = $2;
   ```

   ```sql
   -- remove_recipe_author.sql
   update recipe set author = null where id = $1;
   ```

2. **Use sentinel values in SQL** when duplication is impractical:

   ```sql
   -- update_recipe.sql
   update recipe
   set
     author =
       case $1
         when '00000000-0000-0000-0000-000000000000' then null
         else $1::uuid
       end,
     description =
       case $2
         when '' then null
         else $2
       end
   where id = $3;
   ```

   Extract repeated logic into SQL functions when queries grow:

   ```sql
   create function string_or_null(value text)
     returns text
     language sql
     immutable
     return nullif(value, "");
   ```

## Command queries

Queries that do not return rows — for example `insert`, `update`, or `delete` without
a `returning` clause — generate raising functions that return `:ok`:

```sql
-- delete_user.sql
delete from users where id = $1
```

```elixir
@spec delete_user(Postgrex.conn(), integer()) :: :ok
def delete_user(conn, id) do
  # ...
end
```

## Soft companions (additive)

Every query also gets a soft companion named `<name>_ok/arity` that uses
`Postgrex.query/3` and returns `{:ok, result} | {:error, Exception.t()}` instead of
raising. This is **additive** — existing raising functions keep the same names and
return shapes.

```elixir
@spec find_user_ok(Postgrex.conn(), integer()) ::
        {:ok, [find_user_row()]} | {:error, Exception.t()}
def find_user_ok(conn, id) do
  # ...
end

@spec delete_user_ok(Postgrex.conn(), integer()) ::
        {:ok, non_neg_integer()} | {:error, Exception.t()}
def delete_user_ok(conn, id) do
  # ...
end
```

Soft command companions return the affected-row count as `{:ok, num_rows}`. Soft
companions for query names ending in `!` or `?` strip that suffix before adding
`_ok` (for example `save!` → `save_ok`). If `<name>_ok` already exists as another
query in the same module, the soft companion is omitted to avoid a name collision.

Queries with a `returning` clause produce row maps like any other select.

## Running queries outside Squirrelix

Because queries live in plain `.sql` files, you can run them directly with `psql`,
GUI clients, or migration tools:

```sh
psql my_app_dev -f lib/my_app/accounts/sql/find_user.sql
```

This is one of the main benefits over embedding SQL as strings in Elixir source.

## Next steps

- [Types](types.md) — supported Postgres types and Elixir mappings
- [Configuration](configuration.md) — inference and metadata options
- [Phoenix + CI Cookbook](phoenix.md) — Mix aliases, CI, Ecto coexistence
