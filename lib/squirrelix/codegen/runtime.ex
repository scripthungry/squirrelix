defmodule Squirrelix.Codegen.Runtime do
  @moduledoc false

  # Quoted runtime helpers inlined into generated SQL modules.
  # Kept as real Elixir (`quote`) so the library compile-checks them; generated
  # modules stay self-contained (no SquirrElix runtime dependency).

  alias Squirrelix.TypeMapper

  @spec section([Squirrelix.TypedQuery.t()]) :: String.t()
  def section(queries) when is_list(queries) do
    case sources(queries) do
      [] ->
        ""

      sources ->
        IO.iodata_to_binary([
          "\n\n# --- Runtime helpers ---\n\n",
          Enum.intersperse(sources, "\n\n"),
          "\n"
        ])
    end
  end

  @spec sources([Squirrelix.TypedQuery.t()]) :: [String.t()]
  def sources(queries) when is_list(queries) do
    []
    |> maybe_add_command_helper(queries)
    |> maybe_add_rows_helper(queries)
    |> maybe_add_encode_helpers(queries)
    |> maybe_add_uuid_helpers(queries)
    |> Enum.reverse()
  end

  defp maybe_add_command_helper(sources, queries) do
    if Enum.any?(queries, &(&1.returns == [])) do
      [to_source(command_helpers()) | sources]
    else
      sources
    end
  end

  defp maybe_add_rows_helper(sources, queries) do
    if Enum.any?(queries, &(&1.returns != [])) do
      types = return_types(queries)
      [to_source(rows_helpers(types)) | sources]
    else
      sources
    end
  end

  defp maybe_add_encode_helpers(sources, queries) do
    if Enum.any?(queries, &(&1.params != [])) do
      types = param_types(queries)
      [to_source(encode_helpers(types)) | sources]
    else
      sources
    end
  end

  defp maybe_add_uuid_helpers(sources, queries) do
    param_type_set = param_types(queries)
    return_type_set = return_types(queries)

    encode_uuid? =
      MapSet.member?(param_type_set, :uuid) or list_element_type?(param_type_set, :uuid)

    decode_uuid? =
      MapSet.member?(return_type_set, :uuid) or list_element_type?(return_type_set, :uuid)

    case {encode_uuid?, decode_uuid?} do
      {false, false} -> sources
      flags -> [to_source(uuid_helpers(flags)) | sources]
    end
  end

  defp command_helpers do
    quote do
      @spec decode_command(Postgrex.Result.t()) :: :ok
      defp decode_command(%Postgrex.Result{}) do
        :ok
      end

      @spec decode_command_num_rows(Postgrex.Result.t()) :: non_neg_integer()
      defp decode_command_num_rows(%Postgrex.Result{num_rows: num_rows})
           when is_integer(num_rows) and num_rows >= 0 do
        num_rows
      end
    end
  end

  defp rows_helpers(types) do
    decode_clauses = decode_scalar_asts(types)

    quote do
      defp decode_rows(%Postgrex.Result{rows: rows}, column_specs) do
        Enum.map(rows, &decode_row(&1, column_specs))
      end

      defp decode_row(row, column_specs) do
        column_specs
        |> Enum.zip(row)
        |> Map.new(fn {{name, type, nullable?}, value} ->
          {name, decode_column_value(value, type, nullable?)}
        end)
      end

      defp decode_column_value(value, _type, true) when is_nil(value), do: nil
      defp decode_column_value(value, type, _nullable?), do: decode_scalar(value, type)

      unquote_splicing(decode_clauses)
    end
  end

  @passthrough_decode_types [
    :integer,
    :string,
    :boolean,
    :float,
    :decimal,
    :binary,
    :date,
    :time,
    :naive_datetime,
    :utc_datetime
  ]

  defp decode_scalar_asts(types) do
    passthrough =
      Enum.reduce(@passthrough_decode_types, [], fn type, clauses ->
        add_decode_clause(clauses, types, type, passthrough_decode_ast(type))
      end)

    passthrough
    |> add_decode_clause(types, :map, map_decode_ast())
    |> add_decode_clause(types, :uuid, uuid_decode_ast())
    |> add_list_decode_asts(types)
    |> Kernel.++([
      quote do
        defp decode_scalar(value, _type), do: value
      end
    ])
  end

  defp passthrough_decode_ast(type) do
    quote do
      defp decode_scalar(value, unquote(type)), do: value
    end
  end

  defp map_decode_ast do
    quote do
      defp decode_scalar(value, :map) when is_map(value), do: value
      defp decode_scalar(value, :map) when is_binary(value), do: JSON.decode!(value)
    end
  end

  defp uuid_decode_ast do
    quote do
      defp decode_scalar(value, :uuid) when is_binary(value) and byte_size(value) == 16,
        do: uuid_to_string(value)

      defp decode_scalar(value, :uuid), do: value
    end
  end

  defp add_decode_clause(clauses, types, type, ast) do
    if MapSet.member?(types, type) or list_element_type?(types, type) do
      clauses ++ flatten_quoted(ast)
    else
      clauses
    end
  end

  defp add_list_decode_asts(clauses, types) do
    list_asts =
      types
      |> Enum.filter(&match?({:list, _}, &1))
      |> Enum.uniq()
      |> Enum.reduce([], fn {:list, type} = list_type, acc ->
        [
          quote do
            defp decode_scalar(value, unquote(list_type)) when is_list(value),
              do: Enum.map(value, &decode_scalar(&1, unquote(type)))
          end
          | acc
        ]
      end)
      |> Enum.reverse()

    clauses ++ list_asts
  end

  defp encode_helpers(types) do
    assert_encodable_param_types!(types)

    types
    |> encode_asts()
    |> Kernel.++(flatten_quoted(encode_unsupported_ast()))
    |> then(fn exprs -> {:__block__, [], exprs} end)
  end

  defp encode_asts(types) do
    []
    |> add_encode_clause(types, :integer, encode_integer_ast())
    |> add_encode_clause(types, :string, encode_string_ast())
    |> add_encode_clause(types, :boolean, encode_boolean_ast())
    |> add_encode_clause(types, :float, encode_float_ast())
    |> add_encode_clause(
      types,
      :decimal,
      encode_struct_ast(:decimal, Decimal, quote(do: Decimal.t()))
    )
    |> add_encode_clause(types, :binary, encode_binary_ast())
    |> add_encode_clause(types, :date, encode_struct_ast(:date, Date, quote(do: Date.t())))
    |> add_encode_clause(types, :time, encode_struct_ast(:time, Time, quote(do: Time.t())))
    |> add_encode_clause(
      types,
      :naive_datetime,
      encode_struct_ast(:naive_datetime, NaiveDateTime, quote(do: NaiveDateTime.t()))
    )
    |> add_encode_clause(
      types,
      :utc_datetime,
      encode_struct_ast(:utc_datetime, DateTime, quote(do: DateTime.t()))
    )
    |> add_encode_clause(types, :map, map_encode_ast())
    |> add_encode_clause(types, :uuid, uuid_encode_ast())
    |> add_list_encode_asts(types)
  end

  defp encode_unsupported_ast do
    quote do
      defp encode_value(value, type) do
        raise ArgumentError, "cannot encode #{inspect(value)} as #{inspect(type)}"
      end
    end
  end

  defp assert_encodable_param_types!(types) do
    unsupported =
      types
      |> Enum.reject(&encodable_param_type?/1)
      |> Enum.uniq()
      |> Enum.sort_by(&inspect/1)

    case unsupported do
      [] ->
        :ok

      types ->
        raise ArgumentError,
              "unsupported parameter type(s) for encoding: #{Enum.map_join(types, ", ", &inspect/1)}"
    end
  end

  defp encodable_param_type?({:list, type}), do: encodable_param_type?(type)

  defp encodable_param_type?(type) when is_atom(type) do
    match?({:ok, _}, TypeMapper.normalize_type(type))
  end

  defp encodable_param_type?(_type), do: false

  defp encode_integer_ast do
    quote do
      @spec encode_value(integer(), :integer) :: integer()
      defp encode_value(value, :integer) when is_integer(value), do: value
    end
  end

  defp encode_string_ast do
    quote do
      @spec encode_value(String.t(), :string) :: String.t()
      defp encode_value(value, :string) when is_binary(value), do: value
    end
  end

  defp encode_boolean_ast do
    quote do
      @spec encode_value(boolean(), :boolean) :: boolean()
      defp encode_value(value, :boolean) when is_boolean(value), do: value
    end
  end

  defp encode_float_ast do
    quote do
      @spec encode_value(float(), :float) :: float()
      defp encode_value(value, :float) when is_float(value), do: value
    end
  end

  defp encode_binary_ast do
    quote do
      @spec encode_value(binary(), :binary) :: binary()
      defp encode_value(value, :binary) when is_binary(value), do: value
    end
  end

  defp encode_struct_ast(type, struct_mod, typespec) do
    quote do
      @spec encode_value(unquote(typespec), unquote(type)) :: unquote(typespec)
      defp encode_value(value, unquote(type)) when is_struct(value, unquote(struct_mod)),
        do: value
    end
  end

  defp map_encode_ast do
    quote do
      @spec encode_value(term(), :map) :: binary()
      defp encode_value(value, :map), do: JSON.encode!(value)
    end
  end

  defp uuid_encode_ast do
    quote do
      @spec encode_value(String.t(), :uuid) :: <<_::128>>
      defp encode_value(value, :uuid) when is_binary(value), do: uuid_from_string(value)
    end
  end

  defp add_encode_clause(clauses, types, type, ast) do
    if MapSet.member?(types, type) or list_element_type?(types, type) do
      clauses ++ flatten_quoted(ast)
    else
      clauses
    end
  end

  defp add_list_encode_asts(clauses, types) do
    list_asts =
      types
      |> Enum.filter(&match?({:list, _}, &1))
      |> Enum.uniq()
      |> Enum.reduce([], fn {:list, type} = list_type, acc ->
        inner = typespec_ast(type)

        [
          quote do
            @spec encode_value([unquote(inner)], unquote(list_type)) :: [unquote(inner)]
            defp encode_value(value, unquote(list_type)) when is_list(value),
              do: Enum.map(value, &encode_value(&1, unquote(type)))
          end
          | acc
        ]
      end)
      |> Enum.reverse()
      |> Enum.flat_map(&flatten_quoted/1)

    clauses ++ list_asts
  end

  defp uuid_helpers({true, true}) do
    {:__block__, [],
     flatten_quoted(uuid_to_string_ast()) ++ flatten_quoted(uuid_from_string_ast())}
  end

  defp uuid_helpers({true, false}), do: uuid_from_string_ast()
  defp uuid_helpers({false, true}), do: uuid_to_string_ast()

  defp uuid_to_string_ast do
    quote do
      @spec uuid_to_string(<<_::128>>) :: String.t()
      defp uuid_to_string(uuid) when is_binary(uuid) and byte_size(uuid) == 16 do
        hex = Base.encode16(uuid, case: :lower)

        <<part1::binary-size(8), part2::binary-size(4), part3::binary-size(4),
          part4::binary-size(4), part5::binary>> = hex

        "#{part1}-#{part2}-#{part3}-#{part4}-#{part5}"
      end
    end
  end

  defp uuid_from_string_ast do
    quote do
      @spec uuid_from_string(binary()) :: <<_::128>>
      defp uuid_from_string(string) when is_binary(string) do
        case Base.decode16(String.replace(string, "-", ""), case: :mixed) do
          {:ok, <<_::128>> = uuid} ->
            uuid

          _ ->
            raise ArgumentError, "invalid UUID: #{inspect(string)}"
        end
      end
    end
  end

  defp typespec_ast(type) do
    type
    |> TypeMapper.typespec()
    |> Code.string_to_quoted!()
  end

  defp param_types(queries) do
    queries
    |> Enum.flat_map(fn query -> Enum.map(query.params, & &1.type) end)
    |> MapSet.new()
  end

  defp return_types(queries) do
    queries
    |> Enum.flat_map(fn query -> Enum.map(query.returns, & &1.type) end)
    |> MapSet.new()
  end

  defp list_element_type?(types, element_type) do
    Enum.any?(types, fn
      {:list, ^element_type} -> true
      _ -> false
    end)
  end

  defp flatten_quoted({:__block__, _, exprs}), do: Enum.flat_map(exprs, &flatten_quoted/1)
  defp flatten_quoted(expr), do: [expr]

  # Macro.to_string/1 wraps multi-expression blocks in parentheses, which is
  # invalid at module top-level for attributes/`defp`. Flatten first.
  defp to_source(quoted) do
    quoted
    |> flatten_quoted()
    |> Enum.map_join("\n\n", &Macro.to_string/1)
  end
end
