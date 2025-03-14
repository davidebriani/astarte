defmodule Astarte.RPC.DUP.HandlerRegistry do
  use Horde.Registry

  def start_link(_) do
    Horde.Registry.start_link(__MODULE__, [keys: :unique], name: __MODULE__)
  end

  def init(init_arg) do
    [members: :auto]
    |> Keyword.merge(init_arg)
    |> Horde.Registry.init()
  end
end
