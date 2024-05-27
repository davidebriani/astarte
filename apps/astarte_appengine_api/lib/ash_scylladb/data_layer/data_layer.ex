defmodule AshScyllaDB.DataLayer do
  import Ecto.Query, only: [from: 2]

  alias Astarte.AppEngine.API.Devices.Device
  require Ash.Expr

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
      ],
      partition_key: [
        type: {:list, :atom},
        required: true,
        doc: """
        The attributes used as partition key. Must have at least one item.
        """
      ],
      clustering_key: [
        type: {:list, :atom},
        default: [],
        doc: """
        The attributes used as clustering key, if any.
        """
      ]
    ]
  }

  @behaviour Ash.DataLayer

  @sections [@scylladb]

  @verifiers [
    AshScyllaDB.DataLayer.Verifiers.VerifyPartitionAndClusteringKeys
  ]

  @moduledoc """
  A ScyllaDB data layer that leverages Ecto's Scylla capabilities.
  """

  use Spark.Dsl.Extension,
    sections: @sections,
    verifiers: @verifiers

  require Logger

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :multitenancy), do: true
  def can?(_, :select), do: true
  def can?(_, :limit), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, :filter), do: true
  def can?(_, :nested_expressions), do: true
  def can?(_, {:filter_expr, _}), do: true
  def can?(_, :sort), do: true
  def can?(_, :distinct_sort), do: false
  def can?(_, :distinct), do: false
  def can?(_, {:sort, _}), do: true
  def can?(_, :composite_primary_key), do: true

  def can?(resource, op) do
    Logger.info("Requested: can?(#{inspect(resource)}, #{inspect(op)})")
    false
  end

  @impl true
  def resource_to_query(resource, _) do
    from(row in {AshScyllaDB.DataLayer.Info.table(resource) || "", resource}, [])
  end

  @impl true
  def set_context(resource, data_layer_query, context) do
    AshSql.Query.set_context(resource, data_layer_query, AshScyllaDB.SqlImplementation, context)
  end

  @impl true
  def limit(query, nil, _), do: {:ok, query}

  def limit(query, limit, _resource) do
    {:ok, from(row in query, limit: ^limit)}
  end

  @impl true
  def select(query, select, resource) do
    query = AshSql.Bindings.default_bindings(query, resource, AshScyllaDB.SqlImplementation)

    {:ok,
     from(row in query,
       select: struct(row, ^Enum.uniq(select))
     )}
  end

  @impl true
  def filter(query, filter, resource) do
    with {:ok, filter} <- adjust_clustering_key_filter(filter, resource),
         {:ok, query} <- AshSql.Filter.filter(query, filter, resource) do
      {:ok, populate_allow_filtering_conditions(query, filter.expression, resource)}
    end
  end

  # TODO: ugly, but 1) make it work 2) make it beautiful.
  # Here we've hardcoded a specific expression, but the high level idea would be:
  # if a filter involves the clustering key and it's not an equality filter (i.e. == and IN),
  # wrap both the lhs and rhs of the filter in `token()`. This allows Ash to make keyset
  # pagination work
  defp adjust_clustering_key_filter(
         %{expression: %{left: %{attribute: %{name: :device_id}}}} = filter,
         Device
       ) do
    # TODO: this should be handled at the DeviceId type level but I didn't find a smart way to do it
    # without shaving too many yaks
    uuid = device_id_to_uuid!(filter.expression.right)

    # We're not handling all possible operations but this works fine for our current usecase
    expr =
      case filter.expression do
        %Ash.Query.Operator.GreaterThan{} ->
          Ash.Expr.expr(fragment("token(device_id) > token(?)", ^uuid))

        %Ash.Query.Operator.LessThan{} ->
          Ash.Expr.expr(fragment("token(device_id) < token(?)", ^uuid))
      end

    context = %{resource: Device}

    with {:ok, hydrated} <- Ash.Filter.hydrate_refs(expr, context) do
      {:ok, %{filter | expression: hydrated}}
    end
  end

  defp adjust_clustering_key_filter(filter, _resource), do: {:ok, filter}

  defp device_id_to_uuid!(device_id) do
    {:ok, decoded_id} = Astarte.Core.Device.decode_device_id(device_id)
    Ecto.UUID.cast!(decoded_id)
  end

  # TODO: simplified, just demonstrating it's feasible
  defp populate_allow_filtering_conditions(query, %{left: %{attribute: %{name: name}}}, Device)
       when name != :device_id do
    # The idea here is to use introspection on the resource to mark the query with allow filtering
    # conditions. We then check them in `run_query` to decide if we should pass ALLOW FILTERING
    # We can't do it directly here because the conditions are complex and depend on multiple filters
    Map.update!(query, :__ash_bindings__, &Map.put(&1, :filter_on_non_primary_key?, true))
  end

  defp populate_allow_filtering_conditions(query, %Ash.Query.BooleanExpression{} = expr, resource) do
    query
    |> populate_allow_filtering_conditions(expr.left, resource)
    |> populate_allow_filtering_conditions(expr.right, resource)
  end

  defp populate_allow_filtering_conditions(query, _filter, _resource), do: query

  @impl true
  def sort(query, sort, Device) do
    # TODO: we silently drop sort for now to make pagination work.
    # We should instead accept sort only on clustering keys _only_ if we have
    # an equality filter (== or IN) on the clustering key, since that's the
    # only operation allowed by Scylla
    {:ok, query}
  end

  @impl true
  def set_tenant(_resource, query, tenant) do
    {:ok, Map.put(Ecto.Query.put_query_prefix(query, to_string(tenant)), :__tenant__, tenant)}
  end

  @impl true
  def run_query(query, resource) do
    with {:ok, query} <- apply_sort(query, resource) do
      query = maybe_allow_filtering(query, resource)
      primary_key = Ash.Resource.Info.primary_key(resource)
      repo = AshSql.dynamic_repo(resource, AshScyllaDB.SqlImplementation, query)
      opts = repo_opts(repo, nil, resource)

      {:ok,
       repo.all(query, opts)
       |> Enum.uniq_by(&Map.take(&1, primary_key))}
    end
  rescue
    e ->
      handle_raised_error(e, __STACKTRACE__, query, resource)
  end

  defp apply_sort(query, resource) do
    if query.__ash_bindings__[:sort_applied?] do
      {:ok, query}
    else
      # :direct since ScyllaDB doesn't support :window
      # TODO: here is where we should check if we can sort or not (see sort/3)
      AshSql.Sort.apply_sort(query, query.__ash_bindings__[:sort], resource, :direct)
    end
  end

  defp maybe_allow_filtering(query, _resource) do
    allow_filtering? =
      cond do
        # If we're filtering on a non primary key
        query.__ash_bindings__[:filter_on_non_primary_key?] ->
          true

        true ->
          false
      end

    if allow_filtering? do
      from(row in query, hints: "ALLOW FILTERING")
    else
      query
    end
  end

  @impl true
  def create(resource, changeset) do
    ecto_changeset =
      changeset.data
      |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource, changeset)))
      |> ecto_changeset(changeset, :create)

    tenant = Map.get(changeset, :to_tenant, changeset.tenant)
    repo = AshSql.dynamic_repo(resource, AshScyllaDB.SqlImplementation, changeset)
    opts = repo_opts(repo, tenant, resource)

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

  defp repo_opts(repo, tenant, resource) do
    opts = AshSql.repo_opts(repo, AshScyllaDB.SqlImplementation, nil, tenant, resource)
    # TODO: should probably be exposed from the Data Layer config
    Keyword.put(opts, :uuid_format, :binary)
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
