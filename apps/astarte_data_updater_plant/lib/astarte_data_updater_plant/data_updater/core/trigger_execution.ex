defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.TriggerExecution do
  @moduledoc """
  Contains logic for executing triggers related to incoming data, value changes, and device errors.
  Extracted from Impl for testability and separation of concerns.
  """
  alias Astarte.DataUpdaterPlant.DataUpdater.Core
  alias Astarte.DataUpdaterPlant.TriggersHandler
  alias Cyanide

  def execute_incoming_data_triggers(
        state,
        device,
        interface,
        interface_id,
        path,
        endpoint_id,
        payload,
        value,
        timestamp
      ) do
    realm = state.realm

    # any interface triggers
    Core.Interface.get_on_data_triggers(state, :on_incoming_data, :any_interface, :any_endpoint)
    |> Enum.each(fn trigger ->
      target_with_policy_list = get_target_with_policy_list(state, trigger)

      TriggersHandler.incoming_data(
        target_with_policy_list,
        realm,
        device,
        interface,
        path,
        payload,
        timestamp
      )
    end)

    # any endpoint triggers
    Core.Interface.get_on_data_triggers(state, :on_incoming_data, interface_id, :any_endpoint)
    |> Enum.each(fn trigger ->
      target_with_policy_list = get_target_with_policy_list(state, trigger)

      TriggersHandler.incoming_data(
        target_with_policy_list,
        realm,
        device,
        interface,
        path,
        payload,
        timestamp
      )
    end)

    # incoming data triggers
    Core.Interface.get_on_data_triggers(
      state,
      :on_incoming_data,
      interface_id,
      endpoint_id,
      path,
      value
    )
    |> Enum.each(fn trigger ->
      target_with_policy_list = get_target_with_policy_list(state, trigger)

      TriggersHandler.incoming_data(
        target_with_policy_list,
        realm,
        device,
        interface,
        path,
        payload,
        timestamp
      )
    end)

    :ok
  end

  def execute_pre_change_triggers(
        {value_change_triggers, _, _, _},
        realm,
        device_id_string,
        interface_name,
        path,
        previous_value,
        value,
        timestamp,
        trigger_id_to_policy_name_map
      ) do
    old_bson_value = Cyanide.encode!(%{v: previous_value})
    payload = Cyanide.encode!(%{v: value})

    if previous_value != value do
      Enum.each(value_change_triggers, fn trigger ->
        trigger_target_with_policy_list =
          trigger.trigger_targets
          |> Enum.map(fn target ->
            {target, Map.get(trigger_id_to_policy_name_map, target.parent_trigger_id)}
          end)

        TriggersHandler.value_change(
          trigger_target_with_policy_list,
          realm,
          device_id_string,
          interface_name,
          path,
          old_bson_value,
          payload,
          timestamp
        )
      end)
    end

    :ok
  end

  def execute_post_change_triggers(
        {_, value_change_applied_triggers, path_created_triggers, path_removed_triggers},
        realm,
        device,
        interface,
        path,
        previous_value,
        value,
        timestamp,
        trigger_id_to_policy_name_map
      ) do
    old_bson_value = Cyanide.encode!(%{v: previous_value})
    payload = Cyanide.encode!(%{v: value})

    if previous_value == nil and value != nil do
      Enum.each(path_created_triggers, fn trigger ->
        target_with_policy_list =
          trigger.trigger_targets
          |> Enum.map(fn target ->
            {target, Map.get(trigger_id_to_policy_name_map, target.parent_trigger_id)}
          end)

        TriggersHandler.path_created(
          target_with_policy_list,
          realm,
          device,
          interface,
          path,
          payload,
          timestamp
        )
      end)
    end

    if previous_value != nil and value == nil do
      Enum.each(path_removed_triggers, fn trigger ->
        target_with_policy_list =
          trigger.trigger_targets
          |> Enum.map(fn target ->
            {target, Map.get(trigger_id_to_policy_name_map, target.parent_trigger_id)}
          end)

        TriggersHandler.path_removed(
          target_with_policy_list,
          realm,
          device,
          interface,
          path,
          timestamp
        )
      end)
    end

    if previous_value != value do
      Enum.each(value_change_applied_triggers, fn trigger ->
        target_with_policy_list =
          trigger.trigger_targets
          |> Enum.map(fn target ->
            {target, Map.get(trigger_id_to_policy_name_map, target.parent_trigger_id)}
          end)

        TriggersHandler.value_change_applied(
          target_with_policy_list,
          realm,
          device,
          interface,
          path,
          old_bson_value,
          payload,
          timestamp
        )
      end)
    end

    :ok
  end

  def execute_device_error_triggers(state, error_name, error_metadata \\ %{}, timestamp) do
    timestamp_ms = div(timestamp, 10_000)

    trigger_target_with_policy_list =
      Map.get(state.device_triggers, :on_device_error, [])
      |> Enum.map(fn target ->
        {target, Map.get(state.trigger_id_to_policy_name, target.parent_trigger_id)}
      end)

    device_id_string = Astarte.Core.Device.encode_device_id(state.device_id)

    TriggersHandler.device_error(
      trigger_target_with_policy_list,
      state.realm,
      device_id_string,
      error_name,
      error_metadata,
      timestamp_ms
    )

    :ok
  end

  defp get_target_with_policy_list(state, trigger) do
    trigger.trigger_targets
    |> Enum.map(fn target ->
      {target, Map.get(state.trigger_id_to_policy_name, target.parent_trigger_id)}
    end)
  end

  defp get_value_change_triggers(state, interface_id, endpoint_id, path, value) do
    value_change_triggers =
      Core.Interface.get_on_data_triggers(
        state,
        :on_value_change,
        interface_id,
        endpoint_id,
        path,
        value
      )

    value_change_applied_triggers =
      Core.Interface.get_on_data_triggers(
        state,
        :on_value_change_applied,
        interface_id,
        endpoint_id,
        path,
        value
      )

    path_created_triggers =
      Core.Interface.get_on_data_triggers(
        state,
        :on_path_created,
        interface_id,
        endpoint_id,
        path,
        value
      )

    path_removed_triggers =
      Core.Interface.get_on_data_triggers(
        state,
        :on_path_removed,
        interface_id,
        endpoint_id,
        path
      )

    if value_change_triggers != [] or value_change_applied_triggers != [] or
         path_created_triggers != [] do
      {:ok,
       {value_change_triggers, value_change_applied_triggers, path_created_triggers,
        path_removed_triggers}}
    else
      {:no_value_change_triggers, nil}
    end
  end

  def value_change_triggers_info(state, interface_id, endpoint_id, path, value) do
    get_value_change_triggers(state, interface_id, endpoint_id, path, value)
  end
end
