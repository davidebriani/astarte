defmodule Astarte.RPC.DUP.Client do
  @moduledoc """
  Provides RPC functionality for interacting with Astarte DUP services.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      Astarte.RPC.DUP.HandlerRegistry
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  alias Astarte.RPC.DUP.VolatileTrigger

  @spec install_volatile_trigger(String.t(), String.t(), %VolatileTrigger{}, keyword()) :: :ok | {:error, term()}
  @doc """
  Installs a volatile trigger for the realm's device.

  ## Parameters

    - `realm` (`String.t()`): The realm in which the device exists.
    - `device_id` (`String.t()`): The unique device identifier.
    - `volatile_trigger` (`%VolatileTrigger{}`): The volatile trigger to install.
    - `opts` (`keyword()`): Additional options for the operation.
      - `:rpc_timeout` (`timeout()`, default: `5000`): How many milliseconds to wait for a reply,
        or the atom :infinity to wait indefinitely. If no reply is received within the specified
        time, the function call fails and the caller exits.

  ## Returns

    - `:ok` when successful.
    - `{:error, reason}` in case of failure.

  ## Examples

      iex> Astarte.RPC.install_volatile_trigger("myrealm", "device123", %VolatileTrigger{})
      :ok

      iex> Astarte.RPC.install_volatile_trigger("myrealm", "unknown_device", %VolatileTrigger{})
      {:error, :device_not_found}
  """
  def install_volatile_trigger(realm_name, device_id, %VolatileTrigger{} = volatile_trigger, opts \\ []) do
    supported_opts = [
      rpc_timeout: [
        type: :timeout,
        default: 5000
      ]
    ]

    with {:ok, opts} <- NimbleOptions.validate(opts, supported_opts) do
      # TODO: Find one process from VMQ replicas

      GenServer.call(pid, {:install_volatile_trigger, %{
        realm: realm,
        device_id: device_id,
        volatile_trigger: volatile_trigger
      }}, opts[:rpc_timeout])
    end
  end
end
