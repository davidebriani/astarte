defmodule Astarte.RPC.VerneMQ do
@moduledoc """
  Provides RPC functionality for interacting with Astarte VerneMQ services.
  """

  @spec delete_device(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  @doc """
  Deletes a device from the given realm.

  ## Parameters

    - `realm` (`String.t()`): The realm in which the device exists.
    - `device_id` (`String.t()`): The unique device identifier.
    - `opts` (`keyword()`): Additional options for the operation.
      - `:rpc_timeout` (`timeout()`, default: `5000`): How many milliseconds to wait for a reply,
        or the atom :infinity to wait indefinitely. If no reply is received within the specified
        time, the function call fails and the caller exits.

  ## Returns

    - `:ok` when successful.
    - `{:error, reason}` in case of failure.

  ## Examples

      iex> Astarte.RPC.delete_device("myrealm", "device123")
      :ok

      iex> Astarte.RPC.delete_device("myrealm", "device123", discard_state: true)
      :ok

      iex> Astarte.RPC.delete_device("myrealm", "unknown_device")
      {:error, :device_not_found}
  """
  def delete_device(realm, device_id, opts \\ []) do
    supported_opts = [
      rpc_timeout: [
        type: :timeout,
        default: 5000
      ]
    ]

    with {:ok, opts} <- NimbleOptions.validate(opts, supported_opts) do
      # TODO: Find one process from VMQ replicas

      GenServer.call(pid, {:delete_device, %{
        realm: realm,
        device_id: device_id
      }}, opts[:rpc_timeout])
    end
  end

  @spec disconnect_device(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  @doc """
  Disconnects a device from the given realm.

  ## Parameters

    - `realm` (`String.t()`): The realm in which the device exists.
    - `device_id` (`String.t()`): The unique device identifier.
    - `opts` (`keyword()`): Additional options for the operation.
      - `:discard_state` (`boolean()`, default: `false`): If `true`, the device state is discarded.
      - `:rpc_timeout` (`timeout()`, default: `5000`): How many milliseconds to wait for a reply,
        or the atom :infinity to wait indefinitely. If no reply is received within the specified
        time, the function call fails and the caller exits.

  ## Returns

    - `:ok` when successful.
    - `{:error, reason}` in case of failure.

  ## Examples

      iex> Astarte.RPC.disconnect_device("myrealm", "device123")
      :ok

      iex> Astarte.RPC.disconnect_device("myrealm", "device123", discard_state: true)
      :ok

      iex> Astarte.RPC.disconnect_device("myrealm", "unknown_device")
      {:error, :device_not_found}
  """
  def disconnect_device(realm, device_id, opts \\ []) do
    supported_opts = [
      discard_state: [
        type: :boolean,
        default: false
      ],
      rpc_timeout: [
        type: :timeout,
        default: 5000
      ]
    ]

    with {:ok, opts} <- NimbleOptions.validate(opts, supported_opts) do
      # TODO: Find one process from VMQ replicas

      GenServer.call(pid, {:disconnect_device, %{
        realm: realm,
        device_id: device_id,
        discard_state: opts[:discard_state]
      }}, opts[:rpc_timeout])
    end
  end
end
