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
end
