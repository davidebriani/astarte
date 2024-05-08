defmodule AshScyllaDB.SqlImplementation do
  @moduledoc false
  use AshSql.Implementation

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
end
