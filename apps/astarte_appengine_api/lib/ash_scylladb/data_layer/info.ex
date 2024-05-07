defmodule AshScyllaDB.DataLayer.Info do
  @moduledoc "Introspection functions for "

  alias Spark.Dsl.Extension

  @doc "The configured repo for a resource"
  def repo(resource) do
    Extension.get_opt(resource, [:scylladb], :repo, nil, true)
  end

  @doc "The configured table for a resource"
  def table(resource) do
    Extension.get_opt(resource, [:scylladb], :table, nil, true)
  end
end
