defmodule Astarte.RPC.DUP.VolatileTrigger do
  @enforce_keys [
    :object_id,
    :object_type,
    :serialized_simple_trigger,
    :parent_id,
    :simple_trigger_id,
    :serialized_trigger_target
  ]
  defstruct @enforce_keys
end
