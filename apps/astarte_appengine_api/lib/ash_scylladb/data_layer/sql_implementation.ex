defmodule AshScyllaDB.SqlImplementation do
  @moduledoc false
  use AshSql.Implementation

  # This is a callback module to handle the differences between Sql implementations
  # across Ecto based data layers

  @impl true
  def table(resource) do
    AshScyllaDB.DataLayer.Info.table(resource)
  end

  @impl true
  def repo(resource, _kind) do
    AshScyllaDB.DataLayer.Info.repo(resource)
  end

  @impl true
  def schema(_resource) do
    nil
  end

  # These two probably don't make much sense in our case, but otherwise the compiler complains
  # about missing callbacks in the behavior implementation
  @impl true
  def manual_relationship_function, do: :ash_scylladb_join
  @impl true
  def manual_relationship_subquery_function, do: :ash_scylladb_subquery

  # Taken from ash_sqlite and ash_postgres, with some exceptions (see comments below)
  @impl true
  def parameterized_type(type, constraints, no_maps? \\ true)

  def parameterized_type({:parameterized, _} = type, _, _) do
    type
  end

  def parameterized_type({:parameterized, _, _} = type, _, _) do
    type
  end

  def parameterized_type({:in, type}, constraints, no_maps?) do
    parameterized_type({:array, type}, constraints, no_maps?)
  end

  def parameterized_type({:array, type}, constraints, _) do
    case parameterized_type(type, constraints[:items] || [], false) do
      nil ->
        nil

      type ->
        {:array, type}
    end
  end

  def parameterized_type(type, _constraints, false)
      when type in [Ash.Type.Map, Ash.Type.Map.EctoType],
      do: :map

  def parameterized_type(type, _constraints, true)
      when type in [Ash.Type.Map, Ash.Type.Map.EctoType],
      do: nil

  def parameterized_type(type, constraints, no_maps?) do
    if Ash.Type.ash_type?(type) do
      cast_in_query? =
        if function_exported?(Ash.Type, :cast_in_query?, 2) do
          Ash.Type.cast_in_query?(type, constraints)
        else
          Ash.Type.cast_in_query?(type)
        end

      # We _don't_ cast Ash builtin types since Scylla doesn't have wide support
      # for casting primitive types. We still cast custom types so that we can
      # use Exandra types
      if cast_in_query? and not Ash.Type.builtin?(type) do
        type = Ash.Type.ecto_type(type)

        parameterized_type(type, constraints, no_maps?)
      else
        nil
      end
    else
      if is_atom(type) && :erlang.function_exported(type, :type, 1) do
        type =
          if type == :ci_string do
            :citext
          else
            type
          end

        Ecto.ParameterizedType.init(type, constraints || [])
      else
        type
      end
    end
  end

  # Taken from ash_sqlite and ash_postgres
  # The implemenation looks very similar to the one of `Ash.Type.determine_types/2`. It would
  # be great to understand how to maybe rely on that instead of copypasting stuff around.
  @impl true
  def determine_types(mod, values) do
    Code.ensure_compiled(mod)

    cond do
      :erlang.function_exported(mod, :types, 0) ->
        mod.types()

      :erlang.function_exported(mod, :args, 0) ->
        mod.args()

      true ->
        [:any]
    end
    |> Enum.map(fn types ->
      case types do
        :same ->
          types =
            for _ <- values do
              :same
            end

          closest_fitting_type(types, values)

        :any ->
          for _ <- values do
            :any
          end

        types ->
          closest_fitting_type(types, values)
      end
    end)
    |> Enum.filter(fn types ->
      Enum.all?(types, &(vagueness(&1) == 0))
    end)
    |> case do
      [type] ->
        if type == :any || type == {:in, :any} do
          nil
        else
          type
        end

      # There are things we could likely do here
      # We only say "we know what types these are" when we explicitly know
      _ ->
        Enum.map(values, fn _ -> nil end)
    end
  end

  defp closest_fitting_type(types, values) do
    types_with_values = Enum.zip(types, values)

    types_with_values
    |> fill_in_known_types()
    |> clarify_types()
  end

  defp clarify_types(types) do
    basis =
      types
      |> Enum.map(&elem(&1, 0))
      |> Enum.min_by(&vagueness(&1))

    Enum.map(types, fn {type, _value} ->
      replace_same(type, basis)
    end)
  end

  defp replace_same({:in, type}, basis) do
    {:in, replace_same(type, basis)}
  end

  defp replace_same(:same, :same) do
    :any
  end

  defp replace_same(:same, {:in, :same}) do
    {:in, :any}
  end

  defp replace_same(:same, basis) do
    basis
  end

  defp replace_same(other, _basis) do
    other
  end

  defp fill_in_known_types(types) do
    Enum.map(types, &fill_in_known_type/1)
  end

  defp fill_in_known_type(
         {vague_type, %Ash.Query.Ref{attribute: %{type: type, constraints: constraints}}} = ref
       )
       when vague_type in [:any, :same] do
    if Ash.Type.ash_type?(type) do
      type = type |> parameterized_type(constraints, true) |> array_to_in()

      {type || :any, ref}
    else
      type =
        if is_atom(type) && :erlang.function_exported(type, :type, 1) do
          {:parameterized, type, []} |> array_to_in()
        else
          type |> array_to_in()
        end

      {type, ref}
    end
  end

  defp fill_in_known_type(
         {{:array, type}, %Ash.Query.Ref{attribute: %{type: {:array, type}} = attribute} = ref}
       ) do
    {:in, fill_in_known_type({type, %{ref | attribute: %{attribute | type: type}}})}
  end

  defp fill_in_known_type({type, value}), do: {array_to_in(type), value}

  defp array_to_in({:array, v}), do: {:in, array_to_in(v)}

  defp array_to_in({:parameterized, type, constraints}),
    do: {:parameterized, array_to_in(type), constraints}

  defp array_to_in(v), do: v

  defp vagueness({:in, type}), do: vagueness(type)
  defp vagueness(:same), do: 2
  defp vagueness(:any), do: 1
  defp vagueness(_), do: 0
end
