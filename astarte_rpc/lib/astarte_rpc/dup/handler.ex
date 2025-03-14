defmodule Astarte.RPC.DUP.Handler do
  @moduledoc """
  Provides RPC functionality for interacting with Astarte DUP services.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    handler_module = Keyword.fetch!(opts, :handler_module)

    {:ok, %{handler_module: handler_module}}
  end

  @impl true
  def handle_call(request, _from, state) do
    apply(state.handler_module, :handle_rpc, request)
  end
end
