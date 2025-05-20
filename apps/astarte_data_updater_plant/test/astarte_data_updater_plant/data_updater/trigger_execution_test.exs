defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.TriggerExecutionTest do
  use ExUnit.Case, async: true

  alias Astarte.DataUpdaterPlant.DataUpdater.Core.TriggerExecution

  @moduletag :trigger_execution

  describe "value_change_triggers_info/5" do
    test "returns :no_value_change_triggers for empty triggers" do
      state = %{data_triggers: %{}}

      assert {:no_value_change_triggers, nil} =
               TriggerExecution.value_change_triggers_info(state, 1, 1, "/path", 42)
    end

    test "returns :ok tuple for present triggers" do
      trigger = %{
        trigger_targets: [%{parent_trigger_id: 1}],
        path_match_tokens: ["path"],
        value_match_operator: :ANY,
        known_value: 42
      }

      state = %{data_triggers: %{{:on_value_change, 1, 1} => [trigger]}}

      assert {:ok, {[trigger], [], [], []}} =
               TriggerExecution.value_change_triggers_info(state, 1, 1, "/path", 42)
    end
  end

  describe "execute_incoming_data_triggers/9" do
    test "returns :ok for minimal valid input" do
      state = %{realm: "realm", trigger_id_to_policy_name: %{}, data_triggers: %{}}

      assert :ok =
               TriggerExecution.execute_incoming_data_triggers(
                 state,
                 "device",
                 "interface",
                 1,
                 "/path",
                 1,
                 <<0>>,
                 42,
                 1234
               )
    end
  end

  describe "execute_pre_change_triggers/9" do
    test "returns :ok for minimal valid input" do
      assert :ok =
               TriggerExecution.execute_pre_change_triggers(
                 {[], [], [], []},
                 "realm",
                 "dev",
                 "iface",
                 "/path",
                 1,
                 2,
                 1234,
                 %{}
               )
    end
  end

  describe "execute_post_change_triggers/9" do
    test "returns :ok for minimal valid input" do
      assert :ok =
               TriggerExecution.execute_post_change_triggers(
                 {[], [], [], []},
                 "realm",
                 "dev",
                 "iface",
                 "/path",
                 1,
                 2,
                 1234,
                 %{}
               )
    end
  end

  describe "execute_device_error_triggers/4" do
    test "returns :ok for minimal valid input" do
      state = %{
        device_triggers: %{},
        trigger_id_to_policy_name: %{},
        device_id: <<0::128>>,
        realm: "realm"
      }

      assert :ok =
               TriggerExecution.execute_device_error_triggers(state, "error", %{}, 1234)
    end
  end

  @tag :integration
  test "integration with TriggersHandler is covered in integration tests" do
    assert true
  end
end
