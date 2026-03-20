# Distributed Tracing in Astarte

Distributed tracing allows you to track requests as they flow through the various services of the Astarte IoT platform. This provides a holistic view of the system's performance and helps identify issues that span multiple service boundaries.

Astarte uses [OpenTelemetry](https://opentelemetry.io/) (OTEL) for distributed tracing. The implementation is integrated into the Elixir-based services using the official OpenTelemetry Erlang/Elixir SDKs. It captures spans for HTTP requests, AMQP messages, internal RPC calls, and database queries, providing a complete trace of data as it moves through the platform.

## Why

Tracing is invaluable for several reasons:

- **Identifying Bottlenecks**: Pinpoint exactly which service or database query is slowing down a request.
- **Cross-Boundary Context Loss**: Astarte is a distributed system where a single logical operation might start with an HTTP request, trigger an AMQP message, and result in multiple database operations. Tracing ensures the context is preserved across these boundaries (HTTP -> AMQP -> RPC -> DB).
- **Debugging Messaging & RPC**: Track the lifecycle of messages as they are produced and consumed across different exchanges/queues and GenServer boundaries.
- **Performance Benchmarking**: Collect data on how different parts of the system perform under various loads to guide optimization efforts.

## How

### W3C Context Propagation

Astarte follows the [W3C Trace Context](https://www.w3.org/TR/trace-context/) specification for propagating trace information. This ensures compatibility with other tools and services that follow the same standard.

### AMQP Propagation

Since AMQP does not have a native way to propagate trace context like HTTP headers, Astarte injects it manually.

- **Injection**: When a service publishes an AMQP message (e.g., in `Astarte.Events.AMQPEvents.Producer`), it injects the current trace context into the AMQP message headers using `:otel_propagator_text_map.inject/1`.
- **Extraction**: When a service consumes an AMQP message (e.g., in `Astarte.TriggerEngine.AMQPConsumer.AMQPMessageConsumer`), it retrieves the trace context from the headers and links the new spans to the existing trace using `:otel_propagator_text_map.extract/1` and `OpenTelemetry.Ctx.attach/1`.

### RPC Propagation

For internal GenServer and cross-node communication (e.g., `astarte_rpc` and Data Updater Plant calls), the trace context is passed directly within the message payload. The caller appends `OpenTelemetry.Ctx.get_current()` to the GenServer call, and the receiving server extracts and attaches it before processing the request.

### Instrumentation

- **Phoenix Instrumentation**: Web-facing services use `opentelemetry_phoenix` to automatically create spans for incoming HTTP requests.
- **Metadata Enrichment**: To make traces searchable by business entities, plugs across Astarte's APIs (AppEngine, Realm Management, Pairing) enrich the active span with domain-specific OpenTelemetry attributes. Using `OpenTelemetry.Tracer.set_attribute/2`, traces are tagged with `astarte.realm`, `astarte.device_id`, `astarte.hw_id`, and `astarte.interface_name`.
- **Cassandra Instrumentation**: Astarte uses a custom `XandraTracing` module to trace Cassandra queries. It natively hooks into Xandra's `:telemetry` events (`[:xandra, :execute_query, :start]`, etc.) to emit `db.execute_query` spans, enriching them with `db.system`, `db.user`, and the actual `db.statement`.

### Opt-in Configuration

Tracing is designed to be opt-in. By default, if no exporter is configured, the overhead is minimal as spans are not exported. To enable tracing, configure an OTLP exporter endpoint.

## Local Development

To enable tracing during local development, a pre-configured Jaeger instance is provided via Docker Compose.

The `docker-compose.tracing.yml` file sets up the Jaeger service and injects the required `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_RESOURCE_ATTRIBUTES` environment variables into all Astarte microservices.

To start the tracing-enabled environment, run:

```sh
docker-compose -f docker-compose.yml -f docker-compose.tracing.yml up
```

Once your services are running:
1. Perform some actions in Astarte (e.g., make an API request).
2. Open the Jaeger UI at [http://localhost:16686](http://localhost:16686).
3. Select a service (e.g., `astarte-appengine-api`) from the dropdown and click "Find Traces".
4. You can also search by tags like `astarte.realm=myrealm` to find specific traces.

## Production

In a production environment managed by the Astarte Kubernetes Operator, enabling OpenTelemetry involves:

1. **Configuring the OTEL Collector**: It's recommended to run an OpenTelemetry Collector as a sidecar or a standalone deployment to aggregate and forward traces to your backend (e.g., Jaeger, Honeycomb, Grafana Tempo).
2. **Setting Environment Variables**: Configure the `OTEL_EXPORTER_OTLP_ENDPOINT` for Astarte services to point to the collector.
3. **Operator Configuration**: Check the [Astarte Operator documentation](https://github.com/astarte-platform/astarte-kubernetes-operator) for the latest instructions on enabling distributed tracing in production via the Astarte Custom Resource (CR).
