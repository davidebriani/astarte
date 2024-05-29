defmodule AshScyllaDB.ManualRelationship do
  @moduledoc "A behavior for ScyllaDB-specific manual relationship functionality"

  # I've just added this because it was required by the behaviour, I'm not 100% sure it makes
  # sense in ScyllaDB given there are no joins (but maybe they could be "emulated" using manual
  # relationships)

  @callback ash_scylladb_join(
              source_query :: Ecto.Query.t(),
              opts :: Keyword.t(),
              current_binding :: term,
              destination_binding :: term,
              type :: :inner | :left,
              destination_query :: Ecto.Query.t()
            ) :: {:ok, Ecto.Query.t()} | {:error, term}

  @callback ash_scylladb_subquery(
              opts :: Keyword.t(),
              current_binding :: term,
              destination_binding :: term,
              destination_query :: Ecto.Query.t()
            ) :: {:ok, Ecto.Query.t()} | {:error, term}

  defmacro __using__(_) do
    quote do
      @behaviour AshSqlite.ManualRelationship
    end
  end
end
