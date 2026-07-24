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
blocks) are stripped when inferring parameter names from equality comparisons. Comments
inside string literals are ignored for parameter-name inference as well.

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
query. For example:

```sql
select *
from
  users
where
  id = $1
  and email = $2
```

Generates `find_user(conn, id, email)`.

Inference considers equality comparisons, ignores string literals and comments, and
deconflicts names that would shadow the `conn` parameter or other reserved
names.

When the same parameter index appears more than once, Squirrelix renames arguments
to keep generated code valid.

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
a `returning` clause — generate functions that return `:ok`:

```sql
-- delete_user.sql
delete from users where id = $1
```

```elixir
@spec delete_user(Postgrex.conn(), integer()) :: :ok
def delete_user(conn, id) do
```

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
