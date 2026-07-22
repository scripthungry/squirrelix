defmodule SquirrelixirRuntimeDecodingTest do
  use ExUnit.Case, async: false

  alias Squirrelixir.Codegen
  alias Squirrelixir.Column
  alias Squirrelixir.Parameter
  alias Squirrelixir.TypedQuery

  @uuid "550e8400-e29b-41d4-a716-446655440000"
  @uuid_binary <<0x55, 0x0E, 0x84, 0x00, 0xE2, 0x9B, 0x41, 0xD4, 0xA7, 0x16, 0x44, 0x66, 0x55,
                 0x44, 0x00, 0x00>>

  @modules [
    Squirrelixir.RuntimeDecodeHelperTest.SQL,
    Squirrelixir.RuntimeEncodeHelperTest.SQL,
    Squirrelixir.RuntimeCommandTest.SQL,
    Squirrelixir.RuntimeQueryTest.SQL,
    Squirrelixir.RuntimeEnumTest.SQL
  ]

  setup do
    on_exit(fn ->
      for module <- @modules do
        :code.delete(module)
        :code.purge(module)
      end
    end)

    :ok
  end

  describe "postgres enum strings" do
    test "decodes enum columns as plain strings" do
      assert decode_row(["happy"], [%Column{name: "mood", type: :string, nullable?: false}]) ==
               %{mood: "happy"}

      assert decode_row(["sleepy"], [%Column{name: "mood", type: :string, nullable?: true}]) ==
               %{mood: "sleepy"}
    end

    test "encodes enum parameters as plain strings" do
      assert encode_params(["happy"], [:string]) == ["happy"]
      assert encode_params(["1 invalid value"], [:string]) == ["1 invalid value"]
    end

    test "generated query functions round-trip enum strings" do
      query =
        typed_query(
          "update_mood.sql",
          "update_mood",
          "update squirrels set mood = $1 where id = $2 returning mood",
          [
            %Parameter{index: 1, name: "mood", type: :string},
            %Parameter{index: 2, name: "id", type: :integer}
          ],
          [%Column{name: "mood", type: :string, nullable?: false}]
        )

      code =
        Codegen.generate_module(Squirrelixir.RuntimeEnumTest.SQL, [query],
          version: "v-test",
          postgrex: RuntimeEnumMock
        )

      assert code =~ "@spec update_mood(Postgrex.conn(), String.t(), integer())"
      assert code =~ "required(:mood) => String.t()"

      [{module, _bytecode}] = Code.compile_string(code)

      assert module.update_mood(
               {RuntimeEnumMock, self(), %Postgrex.Result{columns: ["mood"], rows: [["sleepy"]]}},
               "sleepy",
               42
             ) == [%{mood: "sleepy"}]

      assert_received {:query!, _, ["sleepy", 42]}
    end
  end

  describe "scalar decoding" do
    test "decodes integer columns" do
      assert decode_row([11], [%Column{name: "res", type: :integer, nullable?: false}]) == %{
               res: 11
             }
    end

    test "decodes string columns" do
      assert decode_row(["wibble"], [%Column{name: "res", type: :string, nullable?: false}]) == %{
               res: "wibble"
             }
    end

    test "decodes float columns" do
      assert decode_row([1.5], [%Column{name: "res", type: :float, nullable?: false}]) == %{
               res: 1.5
             }
    end

    test "decodes boolean columns" do
      assert decode_row([true], [%Column{name: "res", type: :boolean, nullable?: false}]) == %{
               res: true
             }
    end

    test "decodes json columns from maps and JSON strings" do
      assert decode_row([%{"a" => 1}], [%Column{name: "res", type: :map, nullable?: false}]) == %{
               res: %{"a" => 1}
             }

      assert decode_row(["{\"a\": 1}"], [%Column{name: "res", type: :map, nullable?: false}]) ==
               %{
                 res: %{"a" => 1}
               }
    end

    test "decodes jsonb columns" do
      assert decode_row([%{"a" => 1}], [%Column{name: "res", type: :map, nullable?: false}]) == %{
               res: %{"a" => 1}
             }
    end

    test "decodes uuid columns from 16-byte binaries" do
      assert decode_row([@uuid_binary], [%Column{name: "res", type: :uuid, nullable?: false}]) ==
               %{res: @uuid}
    end

    test "decodes date, time, and timestamp columns" do
      date = ~D[1970-01-02]
      time = ~T[12:34:56]
      naive = ~N[1970-01-02 12:34:56]
      utc = DateTime.from_naive!(~N[1970-01-02 12:34:56], "Etc/UTC")

      assert decode_row([date], [%Column{name: "res", type: :date, nullable?: false}]) == %{
               res: date
             }

      assert decode_row([time], [%Column{name: "res", type: :time, nullable?: false}]) == %{
               res: time
             }

      assert decode_row([naive], [
               %Column{name: "res", type: :naive_datetime, nullable?: false}
             ]) == %{res: naive}

      assert decode_row([utc], [%Column{name: "res", type: :utc_datetime, nullable?: false}]) ==
               %{
                 res: utc
               }
    end

    test "decodes bytea, numeric, char, varchar, citext, and name columns" do
      decimal = Decimal.new("1.1")

      assert decode_row([<<97, 97, 97>>], [
               %Column{name: "res", type: :binary, nullable?: false}
             ]) == %{res: <<97, 97, 97>>}

      assert decode_row([decimal], [%Column{name: "res", type: :decimal, nullable?: false}]) == %{
               res: decimal
             }

      for value <- ["a", "varchar", "wibble", "pg_catalog"] do
        assert decode_row([value], [%Column{name: "res", type: :string, nullable?: false}]) == %{
                 res: value
               }
      end
    end
  end

  describe "scalar encoding" do
    test "encodes integer, string, float, and boolean parameters" do
      assert encode_params([11, "wibble", 1.5, true], [:integer, :string, :float, :boolean]) ==
               [11, "wibble", 1.5, true]
    end

    test "encodes json and jsonb parameters" do
      assert ["{\"a\":1}"] = encode_params([%{"a" => 1}], [:map])
    end

    test "encodes uuid parameters" do
      assert encode_params([@uuid], [:uuid]) == [@uuid_binary]
    end

    test "encodes date, time, and timestamp parameters" do
      date = ~D[1970-01-02]
      time = ~T[12:34:56]
      naive = ~N[1970-01-02 12:34:56]
      utc = DateTime.from_naive!(~N[1970-01-02 12:34:56], "Etc/UTC")

      assert encode_params([date, time, naive, utc], [
               :date,
               :time,
               :naive_datetime,
               :utc_datetime
             ]) == [date, time, naive, utc]
    end

    test "encodes bytea, numeric, char, varchar, citext, and name parameters" do
      decimal = Decimal.new("1.1")

      assert encode_params([<<97, 97, 97>>, decimal, "a", "varchar", "wibble", "pg_catalog"], [
               :binary,
               :decimal,
               :string,
               :string,
               :string,
               :string
             ]) == [<<97, 97, 97>>, decimal, "a", "varchar", "wibble", "pg_catalog"]
    end
  end

  describe "optional decoding" do
    test "returns nil for nullable columns without decoding" do
      assert decode_row([nil], [%Column{name: "acorns", type: :integer, nullable?: true}]) == %{
               acorns: nil
             }
    end
  end

  describe "array decoding and encoding" do
    test "decodes and encodes integer arrays" do
      assert decode_row([[1, 2, 3]], [
               %Column{name: "res", type: {:list, :integer}, nullable?: false}
             ]) == %{res: [1, 2, 3]}

      assert encode_params([[1, 2, 3]], [{:list, :integer}]) == [[1, 2, 3]]
    end

    test "decodes and encodes uuid arrays" do
      assert decode_row([[@uuid_binary]], [
               %Column{name: "res", type: {:list, :uuid}, nullable?: false}
             ]) == %{res: [@uuid]}

      assert encode_params([[@uuid]], [{:list, :uuid}]) == [[@uuid_binary]]
    end
  end

  describe "command queries" do
    test "insert_with_no_returned_values_returns_just_ok" do
      query =
        typed_query(
          "insert_squirrel.sql",
          "insert_squirrel",
          "insert into squirrel values ($1, $2)",
          [
            %Parameter{index: 1, name: "name", type: :string},
            %Parameter{index: 2, name: "acorns", type: :integer}
          ],
          []
        )

      code =
        Codegen.generate_module(Squirrelixir.RuntimeCommandTest.SQL, [query],
          version: "v-test",
          postgrex: RuntimeDecodingMock
        )

      refute code =~ "decode_rows"
      assert code =~ "@spec insert_squirrel(Postgrex.conn(), String.t(), integer()) :: :ok"

      [{module, _bytecode}] = Code.compile_string(code)

      assert module.insert_squirrel({RuntimeDecodingMock, self(), command: true}, "sandy", 1000) ==
               :ok

      assert_received {:query!, "insert into squirrel values ($1, $2)", ["sandy", 1000]}
    end
  end

  describe "generated query functions" do
    test "encoding query parameters and decoding returned rows" do
      query =
        typed_query(
          "check_uuid.sql",
          "check_uuid",
          "select true as res where $1 = $2::uuid",
          [
            %Parameter{index: 1, name: "expected", type: :uuid},
            %Parameter{index: 2, name: "actual", type: :uuid}
          ],
          [%Column{name: "res", type: :boolean, nullable?: false}]
        )

      code =
        Codegen.generate_module(Squirrelixir.RuntimeQueryTest.SQL, [query],
          version: "v-test",
          postgrex: RuntimeDecodingMock
        )

      [{module, _bytecode}] = Code.compile_string(code)

      result =
        module.check_uuid(
          {RuntimeDecodingMock, self(), %Postgrex.Result{columns: ["res"], rows: [[true]]}},
          @uuid,
          @uuid
        )

      assert result == [%{res: true}]
      assert_received {:query!, _, params}
      assert params == [@uuid_binary, @uuid_binary]
    end
  end

  defp decode_row(row, columns) do
    query = typed_query("decode.sql", "decode", "select 1", [], columns)

    code =
      Codegen.generate_module(Squirrelixir.RuntimeDecodeHelperTest.SQL, [query],
        version: "v-test",
        postgrex: RuntimeDecodingMock
      )

    [{module, _bytecode}] = Code.compile_string(code)

    module.decode(
      {RuntimeDecodingMock, self(),
       %Postgrex.Result{columns: Enum.map(columns, & &1.name), rows: [row]}}
    )
    |> hd()
  end

  defp encode_params(values, types) do
    params =
      Enum.with_index(types, 1)
      |> Enum.map(fn {type, index} ->
        %Parameter{index: index, name: "arg_#{index}", type: type}
      end)

    query =
      typed_query(
        "encode.sql",
        "encode",
        placeholders(length(params)),
        params,
        []
      )

    code =
      Codegen.generate_module(Squirrelixir.RuntimeEncodeHelperTest.SQL, [query],
        version: "v-test",
        postgrex: RuntimeEncodingCaptureMock
      )

    [{module, _bytecode}] = Code.compile_string(code)

    flush_mailbox()

    apply(module, :encode, [{RuntimeEncodingCaptureMock, self()} | values])
    assert_received {:query!, _, captured}
    captured
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp placeholders(count) do
    1..count
    |> Enum.map_join(", ", &"$#{&1}")
    |> then(&"select #{&1}")
  end

  defp typed_query(file, name, content, params, returns) do
    %TypedQuery{
      file: file,
      starting_line: 1,
      name: name,
      comment: [],
      content: content,
      params: params,
      returns: returns
    }
  end
end

defmodule RuntimeDecodingMock do
  def query!({_module, owner, %Postgrex.Result{} = result}, sql, params) do
    send(owner, {:query!, sql, params})
    result
  end

  def query!({_module, owner, command: true}, sql, params) do
    send(owner, {:query!, sql, params})
    %Postgrex.Result{command: :insert, columns: nil, rows: nil, num_rows: 1}
  end
end

defmodule RuntimeEncodingCaptureMock do
  def query!({_module, owner}, sql, params) do
    send(owner, {:query!, sql, params})
    %Postgrex.Result{command: :select, columns: nil, rows: nil, num_rows: 0}
  end
end

defmodule RuntimeEnumMock do
  def query!({_module, owner, %Postgrex.Result{} = result}, sql, params) do
    send(owner, {:query!, sql, params})
    result
  end
end
