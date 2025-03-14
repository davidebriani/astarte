defmodule Astarte.RPC.DUP.Server do
  @moduledoc """
  Provides RPC functionality for interacting with Astarte DUP services.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    handler_module = Keyword.fetch!(opts, :handler_module)

    children = [
      Astarte.RPC.DUP.HandlerRegistry,
      {handler_module, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
