defmodule SquirrelixCodegenTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Squirrelix.Codegen
  alias Squirrelix.CodegenCheckSummary
  alias Squirrelix.CodegenSummary
  alias Squirrelix.Column
  alias Squirrelix.Error.CannotReadFile
  alias Squirrelix.Error.OutdatedFile
  alias Squirrelix.Parameter
  alias Squirrelix.TypedQuery
  alias Squirrelix.TypeMapper

  test "generate_module emits formatted Elixir functions sorted alphabetically by name" do
    queries = [
      typed_query("z_last.sql", "z_last", "select * from users", []),
      typed_query(
        "a_first.sql",
        "find_user",
        "select * from users where id = $1",
        [
          %Parameter{index: 1, name: "id", type: :integer}
        ],
        [%Column{name: "name", type: :string, nullable?: false}]
      )
    ]

    code = Codegen.generate_module(MyApp.Accounts.SQL, queries, version: "v-test")

    assert code =~ "def find_user(conn, id)"
    assert code =~ "encode_value(id, :integer)"
    assert code =~ "decode_rows([{:name, :string, false}])"
    assert code =~ "def z_last(conn)"
    assert code =~ "decode_rows([{:id, :integer, false}])"
    assert code =~ "defp decode_row("
    assert code =~ "@type column_spec ::"
    assert code =~ "defp decode_column_value("
    assert function_position(code, "find_user") < function_position(code, "z_last")
  end

  test "generate_module sorts queries by source file path like Gleam" do
    queries = [
      typed_query("a_last.sql", "zebra", "select 1 as res", [], [
        %Column{name: "res", type: :integer, nullable?: false}
      ]),
      typed_query("z_first.sql", "apple", "select 2 as res", [], [
        %Column{name: "res", type: :integer, nullable?: false}
      ])
    ]

    code = Codegen.generate_module(MyApp.SQL, queries, version: "v-test")

    assert function_position(code, "zebra") < function_position(code, "apple")
  end

  test "generate_module emits a runtime helpers section" do
    query =
      typed_query("find_user.sql", "find_user", "select name from users", [], [
        %Column{name: "name", type: :string, nullable?: false}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "# --- Runtime helpers ---"
    assert code =~ ~r/end\n\n  # --- Runtime helpers ---\n\n  defp decode_rows/
    refute code =~ ~r/end\n\n\n  # --- Runtime helpers ---/
    refute code =~ "@spec decode_rows("
  end

  test "generate_module deduplicates uuid helpers when multiple queries use uuids" do
    uuid_query = fn name, file ->
      typed_query(file, name, "select gen_random_uuid()", [], [
        %Column{name: "gen_random_uuid", type: :uuid, nullable?: false}
      ])
    end

    queries = [
      uuid_query.("one", "one.sql"),
      uuid_query.("other", "other.sql")
    ]

    code = Codegen.generate_module(MyApp.SQL, queries, version: "v-test")

    assert Regex.scan(~r/defp uuid_to_string\(/, code) |> length() == 1
    refute code =~ "defp uuid_from_string("
    assert function_position(code, "one") < function_position(code, "other")
  end

  test "generate_module rejects unsupported parameter types for encoding" do
    bad_atom =
      typed_query("bad.sql", "bad", "select $1", [
        %Parameter{index: 1, name: "x", type: :inet}
      ])

    assert_raise ArgumentError, ~r/unsupported parameter type\(s\).*\:inet/, fn ->
      Codegen.generate_module(MyApp.SQL, [bad_atom], version: "v-test")
    end

    bad_list =
      typed_query("bad_list.sql", "bad_list", "select $1", [
        %Parameter{index: 1, name: "xs", type: {:list, :inet}}
      ])

    assert_raise ArgumentError, ~r/unsupported parameter type\(s\).*\{:list, :inet\}/, fn ->
      Codegen.generate_module(MyApp.SQL, [bad_list], version: "v-test")
    end
  end

  test "generate_module emits a catch-all encode_value clause" do
    query =
      typed_query("encode.sql", "encode", "select $1", [
        %Parameter{index: 1, name: "id", type: :integer}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ ~r/defp encode_value\(value, type\) do/
    assert code =~ "cannot encode"
  end

  test "generate_module uses String.t() for multiple enum-using queries without enum modules" do
    queries = [
      typed_query(
        "find_by_mood.sql",
        "find_by_mood",
        "select mood from squirrels where mood = $1",
        [%Parameter{index: 1, name: "mood", type: :string}],
        [%Column{name: "mood", type: :string, nullable?: false}]
      ),
      typed_query(
        "find_by_colour.sql",
        "find_by_colour",
        "select colour from squirrels where colour = $1",
        [%Parameter{index: 1, name: "colour", type: :string}],
        [%Column{name: "colour", type: :string, nullable?: false}]
      )
    ]

    code = Codegen.generate_module(MyApp.SQL, queries, version: "v-test")

    assert code =~ "@spec find_by_colour(Postgrex.conn(), String.t()) :: [find_by_colour_row()]"
    assert code =~ "@spec find_by_mood(Postgrex.conn(), String.t()) :: [find_by_mood_row()]"
    assert code =~ "required(:colour) => String.t()"
    assert code =~ "required(:mood) => String.t()"
    refute code =~ "SquirrelColour"
    refute code =~ "SquirrelMood"
    refute code =~ "_decoder"
    refute code =~ "_encoder"
    refute code =~ "# --- Enums ---"
    assert function_position(code, "find_by_colour") < function_position(code, "find_by_mood")
  end

  test "generate_module uses String.t() when a query uses multiple enum strings" do
    query =
      typed_query(
        "query.sql",
        "query",
        "select 'red'::squirrel_colour where $1 = 'gleamy'::squirrel_mood",
        [%Parameter{index: 1, name: "mood", type: :string}],
        [%Column{name: "squirrel_colour", type: :string, nullable?: false}]
      )

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "@spec query(Postgrex.conn(), String.t()) :: [query_row()]"
    assert code =~ "required(:squirrel_colour) => String.t()"
    refute code =~ "SquirrelColour"
    refute code =~ "SquirrelMood"
    refute code =~ "# --- Enums ---"
  end

  test "generate_module maps postgres enums to String.t() and round-trips at runtime" do
    query =
      typed_query(
        "find_by_mood.sql",
        "find_by_mood",
        "select mood from squirrels where mood = $1",
        [
          %Parameter{index: 1, name: "mood", type: :string}
        ],
        [%Column{name: "mood", type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedEnumTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexEnumMock
      )

    assert code =~ "@spec find_by_mood(Postgrex.conn(), String.t()) :: [find_by_mood_row()]"
    assert code =~ "required(:mood) => String.t()"
    refute code =~ "Mood"
    refute code =~ "enum"

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.find_by_mood({PostgrexEnumMock, self()}, "happy") == [%{mood: "happy"}]
    assert_received {:query!, "select mood from squirrels where mood = $1", ["happy"]}
  end

  test "generate_module maps json columns to term() specs" do
    query =
      typed_query("payload.sql", "payload", "select payload from events", [], [
        %Column{name: "payload", type: :map, nullable?: false}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "required(:payload) => term()"
    assert code =~ "@type payload_row :: %{required(:payload) => term()}"
  end

  test "generate_module uses fallback argument names when SQL inference could not name a parameter" do
    query =
      typed_query("search.sql", "search", "select * from users where $1 is null", [
        %Parameter{index: 1, name: nil, type: :string}
      ])

    assert Codegen.generate_module(MyApp.SQL, [query], version: "v-test") =~
             "def search(conn, arg_1)"
  end

  test "generate_module deconflicts argument names" do
    query =
      typed_query("conflicting.sql", "conflicting", "select $1, $2, $3", [
        %Parameter{index: 1, name: "conn", type: :string},
        %Parameter{index: 2, name: "conn", type: :string},
        %Parameter{index: 3, name: "arg_1", type: :string}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "def conflicting(conn, conn_1, conn_2, arg_1)"
    assert code =~ "encode_value(conn_1, :string)"
    assert code =~ "encode_value(conn_2, :string)"
    assert code =~ "encode_value(arg_1, :string)"
  end

  test "generate_module avoids Elixir reserved argument names" do
    query =
      typed_query("reserved.sql", "reserved", "select $1, $2, $3", [
        %Parameter{index: 1, name: "fn", type: :string},
        %Parameter{index: 2, name: "end", type: :string},
        %Parameter{index: 3, name: "type", type: :string}
      ])

    code =
      Codegen.generate_module(Squirrelix.GeneratedReservedNamesTest.SQL, [query],
        version: "v-test"
      )

    assert code =~ "def reserved(conn, fn_, end_, type)"
    assert code =~ "encode_value(fn_, :string)"
    assert code =~ "encode_value(end_, :string)"
    assert code =~ "encode_value(type, :string)"

    assert [{Squirrelix.GeneratedReservedNamesTest.SQL, _bytecode}] =
             Squirrelix.TestSupport.compile_string(code)
  end

  test "generate_module avoids SQL literal argument names" do
    query =
      typed_query("literals.sql", "literals", "select $1, $2, $3", [
        %Parameter{index: 1, name: "true", type: :boolean},
        %Parameter{index: 2, name: "false", type: :boolean},
        %Parameter{index: 3, name: "null", type: :string}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "def literals(conn, arg_1, arg_2, arg_3)"
    assert code =~ "encode_value(arg_1, :boolean)"
    assert code =~ "encode_value(arg_2, :boolean)"
    assert code =~ "encode_value(arg_3, :string)"
  end

  test "generate_module avoids invalid argument names" do
    query =
      typed_query("invalid_names.sql", "invalid_names", "select $1, $2", [
        %Parameter{index: 1, name: "123_invalid", type: :string},
        %Parameter{index: 2, name: "has-dash", type: :string}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "def invalid_names(conn, arg_1, arg_2)"
    assert code =~ "encode_value(arg_1, :string)"
    assert code =~ "encode_value(arg_2, :string)"
  end

  test "generate_module renames arguments that would shadow decoder helpers" do
    query =
      typed_query("shadow_decoder.sql", "shadow_decoder", "select decoder where $1 = decoder", [
        %Parameter{index: 1, name: "decoder", type: :integer}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "def shadow_decoder(conn, decoder_1)"
    assert code =~ "encode_value(decoder_1, :integer)"
  end

  test "generate_module renames arguments that would shadow encoder helpers" do
    query =
      typed_query("shadow_encoder.sql", "shadow_encoder", "select encoder where $1 = encoder", [
        %Parameter{index: 1, name: "uuid_encoder", type: :string}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "def shadow_encoder(conn, uuid_encoder_1)"
    assert code =~ "encode_value(uuid_encoder_1, :string)"
  end

  test "generate_module includes Elixir-native row specs via TypeMapper" do
    query =
      typed_query("find_user.sql", "find_user", "select * from users", [], [
        %Column{name: "name", type: :string, nullable?: true},
        %Column{name: "age", type: :integer, nullable?: false}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")
    row_type = row_type_fragment(code, "find_user")
    spec = typespec_fragment(code, "find_user")

    assert row_type =~ "required(:name) => String.t() | nil"
    assert row_type =~ "required(:age) => integer()"

    # Codegen must share TypeMapper for field typespecs (string column names).
    assert String.replace(row_type, ~r/\s+/, "") ==
             String.replace(
               TypeMapper.row_typespec([{"name", :string, true}, {"age", :integer, false}]),
               ~r/\s+/,
               ""
             )

    assert spec == "[find_user_row()]"
  end

  test "generate_module includes nullable columns in row specs" do
    query =
      typed_query("find_user.sql", "find_user", "select * from users", [], [
        %Column{name: "name", type: :string, nullable?: true},
        %Column{name: "age", type: :integer, nullable?: false}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "@type find_user_row ::"
    assert code =~ "@spec find_user(Postgrex.conn()) :: [find_user_row()]"
    assert code =~ "required(:name) => String.t() | nil"
    assert code =~ "required(:age) => integer()"
  end

  test "generate_module maps utc datetimes to DateTime specs" do
    query =
      typed_query("events.sql", "events", "select now()", [], [
        %Column{name: "occurred_at", type: :utc_datetime, nullable?: false}
      ])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ "@type events_row :: %{required(:occurred_at) => DateTime.t()}"
    assert code =~ "@spec events(Postgrex.conn()) :: [events_row()]"
  end

  test "generate_module output is classified as generated" do
    query = typed_query("all.sql", "all", "select * from users", [])

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert Squirrelix.classify_file_content(code) == :likely_generated
  end

  test "generate_module emits query comments as function docs" do
    query = %TypedQuery{
      typed_query("find_user.sql", "find_user", "select * from users", [])
      | comment: ["Finds a user.", "Returns every matching row."]
    }

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    assert code =~ ~s|@doc "Finds a user.\\nReturns every matching row."|
  end

  test "generate_module embeds SQL and docs without Elixir interpolation" do
    query = %TypedQuery{
      typed_query(
        "find_user.sql",
        "find_user",
        ~S|select '#{1 + 1}' as label|,
        []
      )
      | comment: [~S|Uses #{System.cmd("true", [])} and """ in the doc|]
    }

    code =
      Codegen.generate_module(Squirrelix.GeneratedInterpolationTest.SQL, [query],
        version: "v-test"
      )

    assert code =~ ~S|select '\#{1 + 1}' as label|
    refute code =~ ~s|select '2' as label|
    assert code =~ "System.cmd"
    assert code =~ ~S|\#{|
    refute code =~ "@doc \"\"\""

    assert [{Squirrelix.GeneratedInterpolationTest.SQL, _bytecode}] =
             Code.compile_string(code)
  end

  test "generate_module emits code that compiles against Postgrex" do
    query =
      typed_query("find_user.sql", "find_user", "select * from users where id = $1", [
        %Parameter{index: 1, name: "id", type: :integer}
      ])

    code =
      Codegen.generate_module(Squirrelix.GeneratedCompileTest.SQL, [query], version: "v-test")

    assert Code.ensure_loaded?(Postgrex)

    assert [{Squirrelix.GeneratedCompileTest.SQL, _bytecode}] =
             Squirrelix.TestSupport.compile_string(code)

    assert function_exported?(Squirrelix.GeneratedCompileTest.SQL, :find_user, 2)
  end

  test "generated functions return decoded row maps" do
    query =
      typed_query(
        "find_user.sql",
        "find_user",
        "select name from users where id = $1",
        [
          %Parameter{index: 1, name: "id", type: :integer}
        ],
        [%Column{name: "name", type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedRuntimeTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexMock
      )

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.find_user({PostgrexMock, self()}, 123) == [%{name: "Ada"}]

    assert_received {:query!, "select name from users where id = $1", [123]}
  end

  test "generated functions decode multiple rows and empty results" do
    query =
      typed_query("list_users.sql", "list_users", "select name from users", [], [
        %Column{name: "name", type: :string, nullable?: false}
      ])

    code =
      Codegen.generate_module(Squirrelix.GeneratedRowsTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexRowsMock
      )

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.list_users({PostgrexRowsMock, self(), rows: [["Ada"], ["Grace"]]}) == [
             %{name: "Ada"},
             %{name: "Grace"}
           ]

    assert module.list_users({PostgrexRowsMock, self(), rows: []}) == []
  end

  test "generated command functions return ok" do
    query =
      typed_query(
        "insert_user.sql",
        "insert_user",
        "insert into users(name) values ($1)",
        [%Parameter{index: 1, name: "name", type: :string}],
        []
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedCommandTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexCommandMock
      )

    assert code =~ "@spec insert_user(Postgrex.conn(), String.t()) :: :ok"

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.insert_user({PostgrexCommandMock, self()}, "Ada") == :ok
    assert_received {:query!, "insert into users(name) values ($1)", ["Ada"]}
  end

  test "generated soft companions use query/3 and keep raising API unchanged" do
    query =
      typed_query(
        "find_user.sql",
        "find_user",
        "select name from users where id = $1",
        [%Parameter{index: 1, name: "id", type: :integer}],
        [%Column{name: "name", type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedSoftRowTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexMock
      )

    assert code =~ "@spec find_user(Postgrex.conn(), integer()) :: [find_user_row()]"
    assert code =~ "def find_user(conn, id)"
    assert code =~ "query!("
    assert code =~ "def find_user_ok(conn, id)"
    assert code =~ ".query("

    assert soft_typespec(code, "find_user_ok") =~
             ~r/\{:ok, \[find_user_row\(\)\]\} \| \{:error, Exception\.t\(\)\}/

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.find_user({PostgrexMock, self()}, 123) == [%{name: "Ada"}]
    assert_received {:query!, "select name from users where id = $1", [123]}

    assert module.find_user_ok({PostgrexMock, self()}, 123) == {:ok, [%{name: "Ada"}]}
    assert_received {:query, "select name from users where id = $1", [123]}
  end

  test "generated soft command companions return ok with num_rows" do
    query =
      typed_query(
        "insert_user.sql",
        "insert_user",
        "insert into users(name) values ($1)",
        [%Parameter{index: 1, name: "name", type: :string}],
        []
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedSoftCommandTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexCommandMock
      )

    assert code =~ "@spec insert_user(Postgrex.conn(), String.t()) :: :ok"

    assert soft_typespec(code, "insert_user_ok") =~
             ~r/\{:ok, non_neg_integer\(\)\} \| \{:error, Exception\.t\(\)\}/

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.insert_user({PostgrexCommandMock, self()}, "Ada") == :ok
    assert_received {:query!, "insert into users(name) values ($1)", ["Ada"]}

    assert module.insert_user_ok({PostgrexCommandMock, self()}, "Ada") == {:ok, 1}
    assert_received {:query, "insert into users(name) values ($1)", ["Ada"]}
  end

  test "soft companions return error tuples without raising" do
    query =
      typed_query(
        "find_user.sql",
        "find_user",
        "select name from users where id = $1",
        [%Parameter{index: 1, name: "id", type: :integer}],
        [%Column{name: "name", type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedSoftErrorTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexSoftErrorMock
      )

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert {:error, %Postgrex.Error{message: "boom"}} =
             module.find_user_ok({PostgrexSoftErrorMock, self()}, 1)

    assert_received {:query, "select name from users where id = $1", [1]}
  end

  test "soft companion for bang-named query strips trailing bang" do
    query =
      typed_query(
        "save!.sql",
        "save!",
        "insert into users(name) values ($1)",
        [%Parameter{index: 1, name: "name", type: :string}],
        []
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedSoftBangNameTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexCommandMock
      )

    assert code =~ "def save!(conn, name)"
    assert code =~ "def save_ok(conn, name)"
    refute code =~ "def save!_ok("
  end

  test "bang-named row queries sanitize type names to valid identifiers" do
    query =
      typed_query(
        "q!.sql",
        "q!",
        "select name from users",
        [],
        [%Column{name: "name", type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedBangRowTypeTest.SQL, [query], version: "v-test")

    assert code =~ "@type q_row ::"
    refute code =~ "@type q!_row"
    assert code =~ "@spec q!(Postgrex.conn()) :: [q_row()]"
    assert code =~ "def q!(conn)"
    assert code =~ "def q_ok(conn)"

    assert soft_typespec(code, "q_ok") =~
             ~r/\{:ok, \[q_row\(\)\]\} \| \{:error, Exception\.t\(\)\}/

    [{_module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)
  end

  test "question-mark row queries sanitize type names to valid identifiers" do
    query =
      typed_query(
        "exists?.sql",
        "exists?",
        "select true as ok",
        [],
        [%Column{name: "ok", type: :boolean, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedQuestionRowTypeTest.SQL, [query],
        version: "v-test"
      )

    assert code =~ "@type exists_row ::"
    refute code =~ "@type exists?_row"
    assert code =~ "@spec exists?(Postgrex.conn()) :: [exists_row()]"
    [{_module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)
  end

  test "generate_module raises when bang and plain names collide on row type" do
    queries = [
      typed_query(
        "q.sql",
        "q",
        "select 1 as n",
        [],
        [%Column{name: "n", type: :integer, nullable?: false}]
      ),
      typed_query(
        "q!.sql",
        "q!",
        "select 2 as n",
        [],
        [%Column{name: "n", type: :integer, nullable?: false}]
      )
    ]

    assert_raise ArgumentError, ~r/row type name collision|q_row/, fn ->
      Codegen.generate_module(Squirrelix.GeneratedRowTypeCollisionTest.SQL, queries,
        version: "v-test"
      )
    end
  end

  test "soft companion is omitted when name collides with another query" do
    queries = [
      typed_query(
        "find_user.sql",
        "find_user",
        "select name from users",
        [],
        [%Column{name: "name", type: :string, nullable?: false}]
      ),
      typed_query(
        "find_user_ok.sql",
        "find_user_ok",
        "select name from users",
        [],
        [%Column{name: "name", type: :string, nullable?: false}]
      )
    ]

    log =
      capture_log(fn ->
        code =
          Codegen.generate_module(Squirrelix.GeneratedSoftCollisionTest.SQL, queries,
            version: "v-test"
          )

        assert code =~ "def find_user(conn)"
        assert code =~ "def find_user_ok(conn)"
        # Soft for find_user would be find_user_ok — skipped due to collision.
        # Soft for find_user_ok is find_user_ok_ok.
        assert code =~ "def find_user_ok_ok(conn)"
        assert [_] = Regex.scan(~r/def find_user_ok\(/, code)
      end)

    assert log =~ "find_user_ok"
    assert log =~ "soft companion" or log =~ "omitting"
  end

  test "soft companions deconflict when bang and plain names share soft base" do
    queries = [
      typed_query(
        "q.sql",
        "q",
        "insert into users(name) values ($1)",
        [%Parameter{index: 1, name: "name", type: :string}],
        []
      ),
      typed_query(
        "q!.sql",
        "q!",
        "insert into users(name) values ($1)",
        [%Parameter{index: 1, name: "name", type: :string}],
        []
      )
    ]

    log =
      capture_log(fn ->
        code =
          Codegen.generate_module(Squirrelix.GeneratedSoftSoftCollisionTest.SQL, queries,
            version: "v-test",
            postgrex: PostgrexCommandMock
          )

        assert code =~ "def q(conn, name)"
        assert code =~ "def q!(conn, name)"
        # Only one soft companion may claim q_ok.
        assert [_] = Regex.scan(~r/def q_ok\(/, code)
      end)

    assert log =~ "q_ok"
    assert log =~ "soft companion" or log =~ "omitting"
  end

  test "write_directory writes a generated module next to the sql directory" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query =
      typed_query(
        Path.join(sql_directory, "find_user.sql"),
        "find_user",
        "select * from users",
        []
      )

    assert Codegen.write_directory(root, sql_directory, [query], version: "v-test") == :ok

    output_file = Path.join(root, "lib/accounts/sql.ex")
    assert File.exists?(output_file)

    assert File.read!(output_file) =~ "defmodule AcornCounter.Accounts.SQL do"
    assert File.read!(output_file) =~ "def find_user(conn)"
  end

  test "write_directory returns error for sql directories outside project source roots" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "priv/sql")
    File.mkdir_p!(sql_directory)

    query =
      typed_query(
        Path.join(sql_directory, "find_user.sql"),
        "find_user",
        "select * from users",
        []
      )

    assert Codegen.write_directory(root, sql_directory, [query], version: "v-test") ==
             {:error, :invalid_sql_directory}
  end

  test "check_directory returns ok when the generated output is current" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query = typed_query(Path.join(sql_directory, "find_user.sql"), "find_user", "select 1", [])

    assert Codegen.write_directory(root, sql_directory, [query], version: "v-test") == :ok
    assert Codegen.check_directory(root, sql_directory, [query], version: "v-test") == :ok
  end

  test "check_directory returns read and outdated errors" do
    root = tmp_project(:acorn_counter)
    sql_directory = Path.join(root, "lib/accounts/sql")
    File.mkdir_p!(sql_directory)

    query = typed_query(Path.join(sql_directory, "find_user.sql"), "find_user", "select 1", [])
    output_file = Path.join(root, "lib/accounts/sql.ex")

    assert Codegen.check_directory(root, sql_directory, [query], version: "v-test") ==
             {:error, %CannotReadFile{file: output_file, reason: :enoent}}

    File.write!(
      output_file,
      Codegen.generate_module(AcornCounter.Accounts.SQL, [], version: "v-test")
    )

    assert Codegen.check_directory(root, sql_directory, [query], version: "v-test") ==
             {:error, %OutdatedFile{file: output_file}}
  end

  test "prepare_directory and write_directory write sibling modules" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    billing_dir = Path.join(root, "lib/billing/sql")

    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(billing_dir)

    accounts_queries = [
      typed_query(Path.join(accounts_dir, "account.sql"), "account", "select 1", [])
    ]

    billing_queries = [
      typed_query(Path.join(billing_dir, "invoice.sql"), "invoice", "select 2", [])
    ]

    assert {:ok, _} =
             Codegen.prepare_directory(root, accounts_dir, accounts_queries, version: "v-test")

    assert Codegen.write_directory(root, accounts_dir, accounts_queries, version: "v-test") == :ok
    assert Codegen.write_directory(root, billing_dir, billing_queries, version: "v-test") == :ok

    assert File.read!(Path.join(root, "lib/accounts/sql.ex")) =~ "def account(conn)"
    assert File.read!(Path.join(root, "lib/billing/sql.ex")) =~ "def invoice(conn)"
  end

  test "check_directory reports missing and current modules" do
    root = tmp_project(:acorn_counter)
    accounts_dir = Path.join(root, "lib/accounts/sql")
    missing_dir = Path.join(root, "lib/missing/sql")

    File.mkdir_p!(accounts_dir)
    File.mkdir_p!(missing_dir)

    accounts_queries = [
      typed_query(Path.join(accounts_dir, "account.sql"), "account", "select 1", [])
    ]

    missing_queries = [
      typed_query(Path.join(missing_dir, "missing.sql"), "missing", "select 2", [])
    ]

    assert Codegen.write_directory(root, accounts_dir, accounts_queries, version: "v-test") == :ok
    assert Codegen.check_directory(root, accounts_dir, accounts_queries, version: "v-test") == :ok

    assert {:error, %CannotReadFile{}} =
             Codegen.check_directory(root, missing_dir, missing_queries, version: "v-test")
  end

  test "summarize_write_outcomes counts generated queries and collects errors" do
    assert Codegen.summarize_write_outcomes([
             {"lib/accounts/sql", :ok, 2},
             {"priv/sql", {:error, :invalid_sql_directory}, 1}
           ]) == %CodegenSummary{
             generated_count: 2,
             errors: [{"priv/sql", :invalid_sql_directory}],
             status: :error
           }
  end

  test "summarize_write_outcomes reports no queries" do
    assert Codegen.summarize_write_outcomes([]) == %CodegenSummary{
             generated_count: 0,
             errors: [],
             status: :empty
           }
  end

  test "summarize_check_outcomes counts checked queries and collects errors" do
    assert Codegen.summarize_check_outcomes([
             {"lib/accounts/sql", :ok, 2},
             {"lib/billing/sql", {:error, :missing}, 1}
           ]) == %CodegenCheckSummary{
             checked_count: 2,
             errors: [{"lib/billing/sql", :missing}],
             status: :error
           }
  end

  test "summarize_check_outcomes reports no queries" do
    assert Codegen.summarize_check_outcomes([]) == %CodegenCheckSummary{
             checked_count: 0,
             errors: [],
             status: :empty
           }
  end

  test "query with quoted string is properly escaped" do
    query =
      typed_query(
        "query.sql",
        "query",
        ~s|select 1 as "result"|,
        [],
        [%Column{name: "result", type: :integer, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedQuotedStringTest.SQL, [query],
        version: "v-test",
        postgrex: PostgrexQuotedStringMock
      )

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)
    assert module.query({PostgrexQuotedStringMock, self()}) == [%{result: 1}]
    assert_received {:query!, ~s|select 1 as "result"|, []}
  end

  test "there is only one empty line between code generated for different queries" do
    queries = [
      typed_query("one.sql", "one", "select 1 as res", [], [
        %Column{name: "res", type: :integer, nullable?: false}
      ]),
      typed_query("two.sql", "two", "select 2 as res", [], [
        %Column{name: "res", type: :integer, nullable?: false}
      ])
    ]

    code = Codegen.generate_module(MyApp.SQL, queries, version: "v-test")

    assert code =~ ~r/end\n\n  @type two_row ::/
    refute code =~ ~r/end\n\n\n  @type two_row ::/
  end

  test "query with many arguments returning nil" do
    params = [
      %Parameter{index: 1, name: nil, type: :string}
      | for index <- 2..9 do
          %Parameter{index: index, name: nil, type: {:list, :string}}
        end
    ]

    content = """
    \nwith a as (
      select $1, *
      from unnest(
        $2::text[],
        $3::text[],
        $4::text[],
        $5::text[],
        $6::text[],
        $7::text[],
        $8::text[],
        $9::text[]
      )
    )
    select
    """

    query = typed_query("query.sql", "query", content, params, [])

    code =
      Codegen.generate_module(Squirrelix.GeneratedManyArgsTest.SQL, [query], version: "v-test")

    assert code =~ "Runs the `query` query defined in `query.sql`."
    assert code =~ ":: :ok"

    assert code =~
             "def query(conn, arg_1, arg_2, arg_3, arg_4, arg_5, arg_6, arg_7, arg_8, arg_9)"

    assert code =~ "Postgrex.conn()"
    assert code =~ "String.t()"

    for _index <- 2..9 do
      assert code =~ "[String.t()]"
    end

    assert code =~ "decode_command()"
    assert [{_module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)
  end

  test "fields appear in the order they have in the select list" do
    query =
      typed_query(
        "query.sql",
        "query",
        "select true as first, 1 as second, 'wibble' as third",
        [],
        [
          %Column{name: "first", type: :boolean, nullable?: false},
          %Column{name: "second", type: :integer, nullable?: false},
          %Column{name: "third", type: :string, nullable?: false}
        ]
      )

    code = Codegen.generate_module(MyApp.SQL, [query], version: "v-test")

    row_type = row_type_fragment(code, "query")

    assert row_type =~ "required(:first) => boolean()"
    assert row_type =~ "required(:second) => integer()"
    assert row_type =~ "required(:third) => String.t()"

    assert field_order(row_type, :first) < field_order(row_type, :second)
    assert field_order(row_type, :second) < field_order(row_type, :third)
    assert code =~ "{:first, :boolean, false}"
    assert code =~ "{:second, :integer, false}"
    assert code =~ "{:third, :string, false}"
  end

  defp function_position(code, function_name) do
    code |> :binary.match("def #{function_name}(") |> elem(0)
  end

  defp typespec_fragment(code, function_name) do
    [_, spec] =
      Regex.run(~r/@spec #{function_name}\([\s\S]*?\) :: ([\s\S]*?)\n  def /, code)

    String.trim(spec)
  end

  defp soft_typespec(code, function_name) do
    [_, spec] =
      Regex.run(~r/@spec #{function_name}\([\s\S]*?\) ::\s*([\s\S]*?)\n  def /, code)

    spec |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  defp row_type_fragment(code, function_name) do
    [_, row_type] =
      Regex.run(~r/@type #{function_name}_row :: ([\s\S]*?)\n  @spec /, code)

    String.trim(row_type)
  end

  test "ecto runner emits Repo-first functions via Ecto.Adapters.SQL" do
    query =
      typed_query(
        "find_user.sql",
        "find_user",
        "select name from users where id = $1",
        [%Parameter{index: 1, name: "id", type: :integer}],
        [%Column{name: "name", type: :string, nullable?: false}]
      )

    code =
      Codegen.generate_module(Squirrelix.GeneratedEctoRunnerTest.SQL, [query],
        version: "v-test",
        runner: :ecto,
        ecto_sql: PostgrexMock
      )

    assert code =~ "@spec find_user(module(), integer()) :: [find_user_row()]"
    assert code =~ "def find_user(repo, id)"
    assert code =~ "PostgrexMock.query!"
    assert code =~ "def find_user_ok(repo, id)"
    assert code =~ "optional Ecto runner"
    refute code =~ "def find_user(conn,"

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.find_user({PostgrexMock, self()}, 123) == [%{name: "Ada"}]
    assert_received {:query!, "select name from users where id = $1", [123]}

    assert module.find_user_ok({PostgrexMock, self()}, 123) == {:ok, [%{name: "Ada"}]}
    assert_received {:query, "select name from users where id = $1", [123]}
  end

  test "ecto runner rejects unknown runner atoms" do
    query = typed_query("q.sql", "q", "select 1 as id", [])

    assert_raise ArgumentError, ~r/unknown codegen runner/, fn ->
      Codegen.generate_module(Squirrelix.GeneratedBadRunner.SQL, [query],
        version: "v-test",
        runner: :mongo
      )
    end
  end

  defp field_order(spec, field) do
    spec |> :binary.match("required(:#{field})") |> elem(0)
  end

  defp typed_query(file, name, content, params, returns \\ nil) do
    %TypedQuery{
      file: file,
      starting_line: 1,
      name: name,
      comment: [],
      content: content,
      params: params,
      returns: returns || [%Column{name: "id", type: :integer, nullable?: false}]
    }
  end

  defp tmp_project(app) do
    path = Squirrelix.TestSupport.tmp_dir!("squirr_elix-codegen")

    File.write!(Path.join(path, "mix.exs"), """
    defmodule TempProject.MixProject do
      use Mix.Project

      def project do
        [app: #{inspect(app)}, version: "0.1.0"]
      end
    end
    """)

    path
  end
end
