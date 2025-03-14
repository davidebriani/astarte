defmodule Astarte.RPC do
  @moduledoc """
  Core module for the Astarte RPC system using Erlang distribution.

  This module provides the primary API for services to perform RPC operations
  using various routing strategies based on the specific needs of each operation.
  """

  @doc """
  Performs an RPC call to a target service.

  ## Parameters

    * `service` - The target service name (e.g. :dup, :vernemq)
    * `request` - The request to be processed
    * `opts` - Options for controlling the RPC behavior
      * `:strategy` - Routing strategy (:any, :specific, :broadcast)
      * `:instance_id` - Required when strategy is :specific
      * `:resource_id` - Optional resource identifier used for consistent routing
      * `:timeout` - Call timeout in milliseconds (default: 5000)

  ## Examples

      # Call any replica of VerneMQ
      Astarte.RPC.call(:vernemq, {:disconnect_device, device_id})

      # Call a specific DUP replica that handles a device
      Astarte.RPC.call(:dup, {:process_data, device_id, payload},
                       strategy: :specific, resource_id: device_id)

      # Broadcast to all replicas of a service
      Astarte.RPC.call(:all_services, {:config_update, new_config},
                       strategy: :broadcast)
  """
  def call(service, request, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :any)
    timeout = Keyword.get(opts, :timeout, 5000)

    case strategy do
      :any ->
        Astarte.RPC.Client.call_any(service, request, timeout)

      :specific ->
        resource_id = Keyword.get(opts, :resource_id)
        instance_id = Keyword.get(opts, :instance_id)

        cond do
          instance_id ->
            Astarte.RPC.Client.call_specific(service, instance_id, request, timeout)
          resource_id ->
            # Let the router determine which instance handles this resource
            Astarte.RPC.Client.call_for_resource(service, resource_id, request, timeout)
          true ->
            raise ArgumentError, "Either instance_id or resource_id must be provided for :specific strategy"
        end

      :broadcast ->
        Astarte.RPC.Client.broadcast(service, request)
    end
  end

  @doc """
  Registers a service handler with the RPC system.

  ## Parameters

    * `service` - The service name to register (e.g. :dup, :vernemq)
    * `handler_module` - Module that will handle requests
    * `opts` - Options for controlling registration behavior
      * `:instance_id` - Optional instance identifier (generated if not provided)
      * `:resource_ranges` - Map of resources this handler is responsible for
      * `:registry_scope` - Registry scope to use (default: :global)
  """
  def register_handler(service, handler_module, opts \\ []) do
    Astarte.RPC.Server.register_handler(service, handler_module, opts)
  end
end

defmodule Astarte.RPC.RegistryManager do
  @moduledoc """
  Manages access to Horde registries for the RPC system.

  This module allows services to create and join different registry scopes
  based on their specific communication needs.
  """
  use GenServer

  # Registry scopes - each service can join multiple scopes
  @registry_scopes [:global, :data_processing, :device_management, :telemetry]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Initialize registry for each scope
    registries = Enum.map(@registry_scopes, fn scope ->
      registry_name = registry_name(scope)

      # Start Horde registry for this scope if not already started
      {:ok, _} = DynamicSupervisor.start_child(
        Astarte.RPC.Supervisor,
        {Horde.Registry, [
          name: registry_name,
          keys: :unique,
          members: :auto
        ]}
      )

      {scope, registry_name}
    end)

    {:ok, %{registries: Map.new(registries)}}
  end

  @doc """
  Registers a handler in one or more registry scopes.
  """
  def register(service, instance_id, pid, scopes \\ [:global]) do
    Enum.each(scopes, fn scope ->
      registry = registry_name(scope)
      Horde.Registry.register(registry, {service, instance_id}, pid)
    end)
  end

  @doc """
  Registers a handler for specific resources.
  """
  def register_for_resources(service, instance_id, pid, resources, scope \\ :global) do
    registry = registry_name(scope)

    # Register the handler for the service general entry
    Horde.Registry.register(registry, {service, instance_id}, pid)

    # Also register the handler for each resource it's responsible for
    Enum.each(resources, fn resource_id ->
      resource_key = {:resource, service, resource_id}
      Horde.Registry.register(registry, resource_key, {instance_id, pid})
    end)
  end

  @doc """
  Looks up a handler for a specific service and instance.
  """
  def lookup_specific(service, instance_id, scope \\ :global) do
    registry = registry_name(scope)
    case Horde.Registry.lookup(registry, {service, instance_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Looks up a handler for a specific resource.
  """
  def lookup_for_resource(service, resource_id, scope \\ :global) do
    registry = registry_name(scope)
    resource_key = {:resource, service, resource_id}

    case Horde.Registry.lookup(registry, resource_key) do
      [{instance_id, pid}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Looks up any handler for a service.
  """
  def lookup_any(service, scope \\ :global) do
    registry = registry_name(scope)

    # Match all instances of this service
    match_pattern = {{service, :_}, :_}

    case Horde.Registry.match(registry, match_pattern, :_) do
      [] -> {:error, :not_found}
      handlers ->
        # Select a random handler
        {pid, _} = Enum.random(handlers)
        {:ok, pid}
    end
  end

  @doc """
  Looks up all handlers for a service.
  """
  def lookup_all(service, scope \\ :global) do
    registry = registry_name(scope)

    # Match all instances of this service
    match_pattern = {{service, :_}, :_}

    case Horde.Registry.match(registry, match_pattern, :_) do
      [] -> {:error, :not_found}
      handlers -> {:ok, Enum.map(handlers, fn {pid, _} -> pid end)}
    end
  end

  # Private helpers

  defp registry_name(scope) do
    Module.concat(Astarte.RPC.Registry, scope |> to_string() |> String.capitalize())
  end
end

defmodule Astarte.RPC.Client do
  @moduledoc """
  Client implementation for the Astarte RPC system.

  This module handles the details of finding and communicating with
  handler processes across the cluster.
  """

  @doc """
  Calls any instance of a service.
  """
  def call_any(service, request, timeout \\ 5000, scope \\ :global) do
    with {:ok, pid} <- Astarte.RPC.RegistryManager.lookup_any(service, scope) do
      GenServer.call(pid, request, timeout)
    else
      {:error, :not_found} ->
        {:error, {:service_not_found, service}}
    end
  end

  @doc """
  Calls a specific instance of a service.
  """
  def call_specific(service, instance_id, request, timeout \\ 5000, scope \\ :global) do
    with {:ok, pid} <- Astarte.RPC.RegistryManager.lookup_specific(service, instance_id, scope) do
      GenServer.call(pid, request, timeout)
    else
      {:error, :not_found} ->
        {:error, {:instance_not_found, service, instance_id}}
    end
  end

  @doc """
  Calls the service instance responsible for a specific resource.
  """
  def call_for_resource(service, resource_id, request, timeout \\ 5000, scope \\ :global) do
    # Try to find the specific handler for this resource
    case Astarte.RPC.RegistryManager.lookup_for_resource(service, resource_id, scope) do
      {:ok, pid} ->
        # Direct call to the handler for this resource
        GenServer.call(pid, request, timeout)

      {:error, :not_found} ->
        # Fallback: hash the resource_id to determine which instance should handle it
        with {:ok, pids} <- Astarte.RPC.RegistryManager.lookup_all(service, scope) do
          # Consistent hashing to pick an instance
          index = :erlang.phash2(resource_id, length(pids))
          pid = Enum.at(pids, index)
          GenServer.call(pid, request, timeout)
        else
          {:error, :not_found} ->
            {:error, {:service_not_found, service}}
        end
    end
  end

  @doc """
  Broadcasts a message to all instances of a service.
  """
  def broadcast(service, request, scope \\ :global) do
    case Astarte.RPC.RegistryManager.lookup_all(service, scope) do
      {:ok, pids} ->
        Enum.each(pids, fn pid -> GenServer.cast(pid, request) end)
        :ok

      {:error, :not_found} ->
        {:error, {:service_not_found, service}}
    end
  end
end

defmodule Astarte.RPC.Server do
  @moduledoc """
  Server implementation for the Astarte RPC system.

  This module handles the registration of handler modules with
  the appropriate Horde registries.
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      # We'll monitor handlers rather than supervise them directly
      # as they'll typically be part of the service's supervision tree
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Registers a handler module with the RPC system.
  """
  def register_handler(service, handler_module, opts \\ []) do
    instance_id = Keyword.get(opts, :instance_id, generate_instance_id())
    scopes = Keyword.get(opts, :registry_scopes, [:global])
    resource_ranges = Keyword.get(opts, :resource_ranges, nil)

    # Get the handler's PID - it should already be started by the service
    pid = GenServer.whereis(handler_module)

    if is_nil(pid) do
      raise "Handler module #{inspect(handler_module)} is not registered as a named process"
    end

    # Monitor the handler to clean up registrations if it goes down
    Process.monitor(pid)

    # Register with the Horde registry
    if resource_ranges do
      # Register with resource-specific mappings
      Enum.each(scopes, fn scope ->
        Astarte.RPC.RegistryManager.register_for_resources(
          service, instance_id, pid, resource_ranges, scope)
      end)
    else
      # Simple registration without resource mapping
      Astarte.RPC.RegistryManager.register(service, instance_id, pid, scopes)
    end

    {:ok, instance_id}
  end

  # Generate a unique instance ID if not provided
  defp generate_instance_id do
    node_string = Node.self() |> to_string() |> String.replace("@", "-")
    random_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{node_string}-#{random_suffix}"
  end

  # Handle down messages for monitored handlers
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Cleanup registrations for this PID
    # This would be implemented to remove the handler from all registries
    {:noreply, state}
  end
end

defmodule Astarte.RPC.Router do
  @moduledoc """
  Routing strategies for Astarte RPC.

  This module implements different routing policies for determining
  which service instance should handle a particular resource.
  """

  @doc """
  Determines which instance should handle a resource based on a consistent hash.
  """
  def route_by_hash(resource_id, instances) do
    # Simple consistent hashing
    hash = :erlang.phash2(resource_id, length(instances))
    Enum.at(instances, hash)
  end

  @doc """
  Routes to a specific instance by ID.
  """
  def route_to_instance(instance_id, instances) do
    Enum.find(instances, fn {id, _pid} -> id == instance_id end)
  end

  @doc """
  Returns a random instance.
  """
  def route_random(instances) do
    Enum.random(instances)
  end
end

defmodule Astarte.RPC.Application do
  @moduledoc """
  Application module for Astarte RPC.

  Sets up the supervision tree for the RPC components.
  """
  use Application

  def start(_type, _args) do
    children = [
      # Main supervisor for dynamic children
      {DynamicSupervisor, name: Astarte.RPC.Supervisor, strategy: :one_for_one},

      # Registry manager
      Astarte.RPC.RegistryManager,

      # Server component
      Astarte.RPC.Server
    ]

    opts = [strategy: :one_for_one, name: Astarte.RPC.Application]
    Supervisor.start_link(children, opts)
  end
end

defmodule Astarte.RPC.Handler do
  @moduledoc """
  Behaviour for RPC handler implementations.

  Defines the callback that handler modules must implement.
  """

  @callback handle_call(request :: term, from :: GenServer.from(), state :: term) ::
    {:reply, reply :: term, new_state :: term} |
    {:reply, reply :: term, new_state :: term, timeout() | :hibernate | {:continue, term}} |
    {:noreply, new_state :: term} |
    {:noreply, new_state :: term, timeout() | :hibernate | {:continue, term}} |
    {:stop, reason :: term, reply :: term, new_state :: term} |
    {:stop, reason :: term, new_state :: term}

  @callback handle_cast(request :: term, state :: term) ::
    {:n
