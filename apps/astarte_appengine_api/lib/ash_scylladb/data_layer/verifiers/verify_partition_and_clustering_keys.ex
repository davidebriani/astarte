defmodule AshScyllaDB.DataLayer.Verifiers.VerifyPartitionAndClusteringKeys do
  # Validates the paginate_relationship_with option
  @moduledoc false

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  def after_compile?, do: true

  def verify(dsl) do
    primary_key_mapset =
      dsl
      |> Ash.Resource.Info.primary_key()
      |> MapSet.new()

    partition_key = Verifier.get_option(dsl, [:scylladb], :partition_key)
    clustering_key = Verifier.get_option(dsl, [:scylladb], :clustering_key, [])

    primary_key_mapset
    |> verify_partition_key!(partition_key, dsl)
    |> verify_clustering_key!(clustering_key, partition_key, dsl)
    |> verify_all_primary_key_columns_covered!(dsl)
  end

  defp verify_partition_key!(primary_key_mapset, partition_key, dsl) do
    Enum.reduce(partition_key, primary_key_mapset, fn partition_column, remaining_primary_key ->
      if MapSet.member?(remaining_primary_key, partition_column) do
        MapSet.delete(remaining_primary_key, partition_column)
      else
        module = Verifier.get_persisted(dsl, :module)

        raise Spark.Error.DslError,
          module: module,
          path: [:scylladb, :partition_key],
          message: """
          #{partition_column} is not part of the primary key, so it can't be part of the \
          partition key.
          """
      end
    end)
  end

  defp verify_clustering_key!(remaining_primary_key, clustering_key, partition_key, dsl) do
    Enum.reduce(clustering_key, remaining_primary_key, fn clustering_column,
                                                          remaining_primary_key ->
      if MapSet.member?(remaining_primary_key, clustering_column) do
        MapSet.delete(remaining_primary_key, clustering_column)
      else
        module = Verifier.get_persisted(dsl, :module)

        # This can also happen if the column was already consumed from the partition key
        if clustering_column in partition_key do
          raise Spark.Error.DslError,
            module: module,
            path: [:scylladb],
            message: """
            partition_key and clustering_key can't contain the same column, but #{clustering_column} \
            is present in both of them.
            """
        else
          raise Spark.Error.DslError,
            module: module,
            path: [:scylladb, :clustering_key],
            message: """
            #{clustering_column} is not part of the primary key, so it can't be part of the \
            clustering key.
            """
        end
      end
    end)
  end

  defp verify_all_primary_key_columns_covered!(remaining_primary_key, dsl) do
    if MapSet.size(remaining_primary_key) == 0 do
      :ok
    else
      module = Verifier.get_persisted(dsl, :module)

      not_covered =
        remaining_primary_key
        |> MapSet.to_list()
        |> Enum.map_join(", ", &to_string/1)

      raise Spark.Error.DslError,
        module: module,
        path: [:scylladb],
        message: """
        partition_key and clustering_key must cover all primary_key columns, but the following \
        columns are not covered: #{not_covered}
        """
    end
  end
end
