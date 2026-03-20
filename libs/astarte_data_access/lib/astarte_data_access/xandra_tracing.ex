#
# This file is part of Astarte.
#
# Copyright 2026 SECO Mind Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

defmodule Astarte.DataAccess.XandraTracing do
  @moduledoc false

  require OpenTelemetry.Tracer, as: Tracer

  require Logger

  def setup do
    require Logger
    Logger.info("Setting up Xandra Telemetry for OpenTelemetry")

    :telemetry.attach_many(
      "otel-xandra-tracer",
      [
        [:xandra, :execute_query, :start],
        [:xandra, :execute_query, :stop],
        [:xandra, :execute_query, :exception],
        [:xandra, :prepare_query, :start],
        [:xandra, :prepare_query, :stop],
        [:xandra, :prepare_query, :exception]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:xandra, type, :start], _measurements, meta, _config) do
    Logger.debug("XandraTracing: start #{type} #{inspect(meta)}")

    span_name = "db.#{type}"
    ctx = Tracer.start_span(span_name, %{kind: :client})

    query = query_string(meta)

    attributes = %{
      "db.system" => "cassandra",
      "db.statement" => query,
      "db.user" => "astarte"
    }

    OpenTelemetry.Span.set_attributes(ctx, attributes)

    # Store ctx in the process dictionary for the :stop or :exception event
    Process.put({__MODULE__, query}, ctx)
  end

  def handle_event([:xandra, _type, :stop], _measurements, meta, _config) do
    Logger.debug("XandraTracing: stop #{inspect(meta)}")

    if ctx = Process.delete({__MODULE__, query_string(meta)}) do
      Tracer.end_span(ctx)
    end
  end

  def handle_event([:xandra, _type, :exception], _measurements, meta, _config) do
    if ctx = Process.delete({__MODULE__, query_string(meta)}) do
      Tracer.set_status(ctx, OpenTelemetry.status(:error, inspect(meta.reason)))
      Tracer.end_span(ctx)
    end
  end

  defp query_string(%{query: %Xandra.Simple{statement: statement}}), do: statement
  defp query_string(%{query: %Xandra.Prepared{statement: statement}}), do: statement
  defp query_string(%{query: %Xandra.Batch{}}), do: "BATCH"
  defp query_string(%{query: query}) when is_binary(query), do: query
  defp query_string(_), do: "UNKNOWN"
end
