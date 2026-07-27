defmodule SquirrelixDialyzerCodegenTest do
  use ExUnit.Case, async: true

  alias Squirrelix.Codegen
  alias Squirrelix.Column
  alias Squirrelix.Parameter
  alias Squirrelix.TypedQuery

  @moduledoc """
  Audits generated modules for Dialyzer-friendly shapes.

  Acceptance (#19): representative row + command queries covering nullable columns,
  arrays, JSON, and UUID emit specs/helpers that stay clean under typical Dialyzer
  flags (`:underspecs`, `:error_handling`, `:unknown`, `:unmatched_returns`).
  """

  test "row query helpers omit underspec'd decode_rows contracts" do
    code = generate!([find_user_query()])

    refute code =~ "@spec decode_rows("
    refute code =~ "@spec decode_row("
    refute code =~ "@spec decode_column_value("
    assert code =~ "defp decode_rows("
    assert code =~ "defp decode_row("
    assert code =~ "defp decode_column_value("
  end

  test "encode helpers emit Dialyzer-friendly specs and guards" do
    code = generate!([find_user_query(), insert_event_query()])

    assert code =~ ~r/@spec encode_value\(integer\(\), :integer\) :: integer\(\)/
    assert code =~ ~r/defp encode_value\(value, :integer\) when is_integer\(value\)/
    assert code =~ ~r/@spec encode_value\(String\.t\(\), :string\) :: String\.t\(\)/
    assert code =~ ~r/defp encode_value\(value, :string\) when is_binary\(value\)/
    assert code =~ ~r/@spec encode_value\(term\(\), :map\) :: binary\(\)/
    assert code =~ ~r/@spec encode_value\(String\.t\(\), :uuid\) :: <<_::128>>/
    assert code =~ ~r/defp encode_value\(value, :uuid\) when is_binary\(value\)/

    assert code =~
             ~r/@spec encode_value\(\[String\.t\(\)\], \{:list, :string\}\) :: \[String\.t\(\)\]/

    assert code =~ ~r/defp encode_value\(value, \{:list, :string\}\) when is_list\(value\)/
  end

  test "command helpers emit non_neg_integer specs and guards" do
    code = generate!([delete_user_query()])

    assert code =~ "@spec decode_command(Postgrex.Result.t()) :: :ok"
    assert code =~ "@spec decode_command_num_rows(Postgrex.Result.t()) :: non_neg_integer()"

    assert code =~
             ~r/defp decode_command_num_rows\(%Postgrex\.Result\{num_rows: num_rows\}\)\n\s+when is_integer\(num_rows\) and num_rows >= 0/
  end

  test "uuid helpers emit precise Dialyzer specs" do
    code = generate!([find_user_query(), insert_event_query()])

    assert code =~ "@spec uuid_to_string(<<_::128>>) :: String.t()"
    assert code =~ "@spec uuid_from_string(binary()) :: <<_::128>>"
  end

  test "nullable, array, json, and uuid appear in precise public row specs" do
    code = generate!([find_user_query()])

    assert code =~ "required(:bio) => String.t() | nil"
    assert code =~ "required(:tags) => [String.t()]"
    assert code =~ "required(:payload) => term() | nil"
    assert code =~ "required(:external_id) => String.t()"

    assert code =~
             "@spec find_user(Postgrex.conn(), integer(), String.t(), [String.t()]) :: [find_user_row()]"

    assert soft_typespec(code, "find_user_ok") =~
             ~r/\{:ok, \[find_user_row\(\)\]\} \| \{:error, Exception\.t\(\)\}/
  end

  test "command and soft companions keep Dialyzer-oriented return specs" do
    code = generate!([delete_user_query()])

    assert code =~ "@spec delete_user(Postgrex.conn(), integer()) :: :ok"

    assert soft_typespec(code, "delete_user_ok") =~
             ~r/\{:ok, non_neg_integer\(\)\} \| \{:error, Exception\.t\(\)\}/
  end

  test "generated module documents Dialyzer expectations" do
    code = generate!([find_user_query()])

    assert code =~ "Dialyzer"
    assert code =~ "overspecs"
  end

  test "representative module compiles and round-trips through mocks" do
    code =
      Codegen.generate_module(Squirrelix.DialyzerRuntimeAudit.SQL, audit_queries(),
        version: "v-test",
        postgrex: PostgrexMock
      )

    [{module, _bytecode}] = Squirrelix.TestSupport.compile_string(code)

    assert module.find_user({PostgrexMock, self()}, 1) == [%{name: "Ada"}]
    assert_received {:query!, _, [1]}
  end

  defp generate!(queries) do
    Codegen.generate_module(MyApp.DialyzerAudit.SQL, queries, version: "v-test")
  end

  defp audit_queries do
    [
      typed_query(
        "find_user.sql",
        "find_user",
        "select name from users where id = $1",
        [%Parameter{index: 1, name: "id", type: :integer}],
        [%Column{name: "name", type: :string, nullable?: false}]
      )
    ]
  end

  defp find_user_query do
    typed_query(
      "find_user.sql",
      "find_user",
      "select id, name, bio, tags, payload, external_id from users where id = $1 and name = $2 and tags && $3",
      [
        %Parameter{index: 1, name: "id", type: :integer},
        %Parameter{index: 2, name: "name", type: :string},
        %Parameter{index: 3, name: "tags", type: {:list, :string}}
      ],
      [
        %Column{name: "id", type: :integer, nullable?: false},
        %Column{name: "name", type: :string, nullable?: false},
        %Column{name: "bio", type: :string, nullable?: true},
        %Column{name: "tags", type: {:list, :string}, nullable?: false},
        %Column{name: "payload", type: :map, nullable?: true},
        %Column{name: "external_id", type: :uuid, nullable?: false}
      ]
    )
  end

  defp delete_user_query do
    typed_query(
      "delete_user.sql",
      "delete_user",
      "delete from users where id = $1",
      [%Parameter{index: 1, name: "id", type: :integer}],
      []
    )
  end

  defp insert_event_query do
    typed_query(
      "insert_event.sql",
      "insert_event",
      "insert into events(payload, external_id) values ($1, $2)",
      [
        %Parameter{index: 1, name: "payload", type: :map},
        %Parameter{index: 2, name: "external_id", type: :uuid}
      ],
      []
    )
  end

  defp soft_typespec(code, function_name) do
    [_, spec] =
      Regex.run(~r/@spec #{function_name}\([\s\S]*?\) ::\s*([\s\S]*?)\n  def /, code)

    spec |> String.replace(~r/\s+/, " ") |> String.trim()
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
