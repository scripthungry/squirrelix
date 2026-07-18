defmodule Squirrelixir.TypeMapper do
  @moduledoc """
  Maps Postgres type names into Squirrelixir's Elixir type metadata.
  """

  alias Squirrelixir.Error.UnsupportedPostgresType

  @base_types %{
    "bool" => :boolean,
    "text" => :string,
    "char" => :string,
    "bpchar" => :string,
    "varchar" => :string,
    "citext" => :string,
    "name" => :string,
    "float4" => :float,
    "float8" => :float,
    "numeric" => :decimal,
    "int2" => :integer,
    "int4" => :integer,
    "int8" => :integer,
    "json" => :map,
    "jsonb" => :map,
    "uuid" => :uuid,
    "bytea" => :binary,
    "date" => :date,
    "time" => :time,
    "timestamp" => :naive_datetime
  }

  @elixir_types MapSet.new([
                  :boolean,
                  :string,
                  :float,
                  :decimal,
                  :integer,
                  :map,
                  :uuid,
                  :binary,
                  :date,
                  :time,
                  :naive_datetime
                ])

  @type elixir_type :: atom() | {:list, elixir_type()}

  @spec from_postgres(String.t(), keyword()) ::
          {:ok, elixir_type()} | {:error, UnsupportedPostgresType.t()}
  def from_postgres(name, opts \\ []) when is_binary(name) and is_list(opts) do
    array_dimensions = Keyword.get(opts, :array_dimensions, 0)

    case Map.fetch(@base_types, name) do
      {:ok, type} -> {:ok, wrap_lists(type, array_dimensions)}
      :error -> {:error, %UnsupportedPostgresType{name: name}}
    end
  end

  @spec normalize_type(term()) :: {:ok, elixir_type()} | {:error, UnsupportedPostgresType.t()}
  def normalize_type({:list, type}) do
    with {:ok, type} <- normalize_type(type) do
      {:ok, {:list, type}}
    end
  end

  def normalize_type(type) when is_atom(type) do
    if MapSet.member?(@elixir_types, type) do
      {:ok, type}
    else
      {:error, %UnsupportedPostgresType{name: Atom.to_string(type)}}
    end
  end

  def normalize_type({:postgres, name}) when is_binary(name) do
    from_postgres(name)
  end

  def normalize_type(%{postgres: name} = descriptor) when is_binary(name) do
    from_postgres(name, array_dimensions: Map.get(descriptor, :array_dimensions, 0))
  end

  defp wrap_lists(type, 0), do: type
  defp wrap_lists(type, count), do: wrap_lists({:list, type}, count - 1)
end
