defmodule AshScyllaDB.DataLayer do
  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Astarte.AppEngine.API.Devices.Device

  @scylladb %Spark.Dsl.Section{
    name: :scylladb,
    describe: """
    Cassandra data layer configuration
    """,
    examples: [
      """
      scylladb do
        repo MyApp.Repo
        table "devices"
      end
      """
    ],
    schema: [
      repo: [
        type: :atom,
        required: true,
        doc: "The repo that will be used to fetch your data."
      ],
      table: [
        type: :string,
        required: true,
        doc: """
        The table to store and read the resource from.
        """
      ]
    ]
  }

  @behaviour Ash.DataLayer

  @sections [@scylladb]

  @moduledoc """
  A ScyllaDB data layer that leverages Ecto's Scylla capabilities.
  """

  use Spark.Dsl.Extension,
    sections: @sections

  require Logger

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :multitenancy), do: true

  def can?(resource, op) do
    Logger.info("Requested: can?(#{inspect(resource)}, #{inspect(op)})")
    false
  end

  @impl true
  def resource_to_query(resource, _) do
    from(row in {AshScyllaDB.DataLayer.Info.table(resource) || "", resource}, [])
  end

  @impl true
  def run_query(query, resource) do
    {:ok, []}
  end

  @impl true
  def create(resource, changeset) do
    ecto_changeset =
      changeset.data
      |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource, changeset)))
      |> ecto_changeset(changeset, :create)

    tenant = Map.get(changeset, :to_tenant, changeset.tenant)

    repo = AshSql.dynamic_repo(resource, AshScyllaDB.SqlImplementation, changeset)

    opts = AshSql.repo_opts(repo, AshScyllaDB.SqlImplementation, nil, tenant, resource)

    try do
      repo.insert(ecto_changeset, opts)
      |> from_ecto()
      |> case do
        {:ok, record} ->
          {:ok, record}

        {:error, error} ->
          handle_errors({:error, error})
      end
    rescue
      e ->
        handle_raised_error(e, __STACKTRACE__, ecto_changeset, resource)
    end
  end

  defp ecto_changeset(record, changeset, type, table_error? \\ true) do
    filters =
      if changeset.action_type == :create do
        %{}
      else
        Map.get(changeset, :filters, %{})
      end

    filters =
      if changeset.action_type == :create do
        filters
      else
        changeset.resource
        |> Ash.Resource.Info.primary_key()
        |> Enum.reduce(filters, fn key, filters ->
          Map.put(filters, key, Map.get(record, key))
        end)
      end

    attributes =
      changeset.resource
      |> Ash.Resource.Info.attributes()
      |> Enum.map(& &1.name)

    attributes_to_change =
      Enum.reject(attributes, fn attribute ->
        Keyword.has_key?(changeset.atomics, attribute)
      end)

    record
    |> to_ecto()
    |> Ecto.Changeset.change(Map.take(changeset.attributes, attributes_to_change))
    |> Map.update!(:filters, &Map.merge(&1, filters))
    |> add_unique_indexes(record.__struct__, changeset)
  end

  def to_ecto(nil), do: nil

  def to_ecto(value) when is_list(value) do
    Enum.map(value, &to_ecto/1)
  end

  def to_ecto(%resource{} = record) do
    if Spark.Dsl.is?(resource, Ash.Resource) do
      resource
      |> Ash.Resource.Info.relationships()
      |> Enum.reduce(record, fn relationship, record ->
        value =
          case Map.get(record, relationship.name) do
            %Ash.NotLoaded{} ->
              %Ecto.Association.NotLoaded{
                __field__: relationship.name,
                __cardinality__: relationship.cardinality
              }

            value ->
              to_ecto(value)
          end

        Map.put(record, relationship.name, value)
      end)
    else
      record
    end
  end

  def to_ecto(other), do: other

  def from_ecto({:ok, result}), do: {:ok, from_ecto(result)}
  def from_ecto({:error, _} = other), do: other

  def from_ecto(nil), do: nil

  def from_ecto(value) when is_list(value) do
    Enum.map(value, &from_ecto/1)
  end

  def from_ecto(%resource{} = record) do
    if Spark.Dsl.is?(resource, Ash.Resource) do
      empty = struct(resource)

      resource
      |> Ash.Resource.Info.relationships()
      |> Enum.reduce(record, fn relationship, record ->
        case Map.get(record, relationship.name) do
          %Ecto.Association.NotLoaded{} ->
            Map.put(record, relationship.name, Map.get(empty, relationship.name))

          value ->
            Map.put(record, relationship.name, from_ecto(value))
        end
      end)
    else
      record
    end
  end

  def from_ecto(other), do: other

  defp handle_errors({:error, %Ecto.Changeset{errors: errors}}) do
    {:error, Enum.map(errors, &to_ash_error/1)}
  end

  defp to_ash_error({field, {message, vars}}) do
    Ash.Error.Changes.InvalidAttribute.exception(
      field: field,
      message: message,
      private_vars: vars
    )
  end

  defp table(resource, changeset) do
    changeset.context[:data_layer][:table] || AshScyllaDB.DataLayer.Info.table(resource)
  end

  defp add_unique_indexes(changeset, resource, ash_changeset) do
    names =
      case Ash.Resource.Info.primary_key(resource) do
        [] ->
          []

        fields ->
          if table = table(resource, ash_changeset) do
            [{fields, table <> "_pkey"}]
          else
            []
          end
      end

    Enum.reduce(names, changeset, fn
      {keys, name}, changeset ->
        Ecto.Changeset.unique_constraint(changeset, List.wrap(keys), name: name)

      {keys, name, message}, changeset ->
        Ecto.Changeset.unique_constraint(changeset, List.wrap(keys), name: name, message: message)
    end)
  end

  defp handle_raised_error(
         %Ecto.StaleEntryError{changeset: %{data: %resource{}, filters: filters}},
         stacktrace,
         context,
         resource
       ) do
    handle_raised_error(
      Ash.Error.Changes.StaleRecord.exception(resource: resource, filters: filters),
      stacktrace,
      context,
      resource
    )
  end

  defp handle_raised_error(%Ecto.Query.CastError{} = e, stacktrace, context, resource) do
    handle_raised_error(
      Ash.Error.Query.InvalidFilterValue.exception(value: e.value, context: context),
      stacktrace,
      context,
      resource
    )
  end

  defp handle_raised_error(error, stacktrace, _ecto_changeset, _resource) do
    {:error, Ash.Error.to_ash_error(error, stacktrace)}
  end
end
