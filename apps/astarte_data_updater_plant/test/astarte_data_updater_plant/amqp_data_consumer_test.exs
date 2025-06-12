#
# This file is part of Astarte.
#
# Copyright 2025 SECO Mind Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
#

defmodule Astarte.DataUpdaterPlant.AMQPDataConsumerTest do
  use Astarte.Cases.Data, async: true
  use Astarte.Cases.Device
  use Mimic
  import ExUnit.CaptureLog
  import Astarte.Helpers.DataUpdater

  require Logger

  alias Astarte.Core.Device
  alias Astarte.DataUpdaterPlant.AMQPDataConsumer
  alias Astarte.DataUpdaterPlant.DataUpdater
  alias Astarte.DataUpdaterPlant.MessageTracker
  alias Astarte.Helpers.Database

  # setup do
  #   device_id = Database.random_device_id()
  #   encoded_device_id = Device.encode_device_id(device_id)
  #   {:ok, device_id: device_id, encoded_device_id: encoded_device_id}
  # end

  setup_all %{realm_name: realm_name, device: device} do
    # Database.insert_device(device.id, realm_name)
    setup_data_updater(realm_name, device.encoded_id)
    state = DataUpdater.dump_state(realm_name, device.encoded_id)

    %{state: state, message_tracker: state.message_tracker}
  end

  # setup do
  #   device_id = Database.random_device_id()
  #   encoded_device_id = Device.encode_device_id(device_id)
  #   %{realm_names: [realm_name]} = setup_instance()

  #   Logger.error(realm_name)

  #   {:ok, device_id: device_id, encoded_device_id: encoded_device_id, realm: realm_name}
  # end

  setup %{realm_name: realm_name, device: device} do
    # on_exit(fn ->
    #   setup_database_access(astarte_instance_id)
    #   # remove_device(device.device_id, realm_name)
    # end)

    # Logger.error(realm_name)
    # {:ok, device} = Database.insert_device(device_id, realm_name)

    queue_index =
      {realm_name, device.encoded_id}
      |> :erlang.phash2(Astarte.DataUpdaterPlant.Config.data_queue_total_count!())

    case Horde.Registry.lookup(Registry.AMQPDataConsumer, {:queue_index, queue_index}) do
      [{pid, _}] ->
        {:ok, consumer: pid}

      [] ->
        flunk(
          "No AMQPDataConsumer process found for queue_index #{queue_index}. Is the app started?"
        )
    end
  end

  setup do
    Mox.verify_on_exit!()
  end

  describe "message handling" do
    test "routes connection messages to handle_connection", context do
      %{realm_name: realm_name, device: device, consumer: pid, message_tracker: message_tracker} =
        context

      device_id = device.encoded_id
      ip = "192.168.1.1"
      timestamp = 1_234_567_890
      payload = "test_payload"
      {message_id, delivery_tag} = tracking_id = tracking_id()

      expect(ExRabbitPool.RabbitMQ, :ack, fn _channel, _delivery_tag, _opts -> :ok end)
      expect(ExRabbitPool.RabbitMQ, :reject, fn _channel, _delivery_tag, _opts -> :ok end)

      expect(DataUpdater, :handle_connection, fn ^realm_name,
                                                 ^device_id,
                                                 ^ip,
                                                 ^tracking_id,
                                                 ^timestamp ->
        :ok
      end)

      expect(MessageTracker, :ack_delivery, fn ^message_tracker, ^message_id -> :ok end)

      headers = [
        {"x_astarte_msg_type", :longstr, "connection"},
        {"x_astarte_realm", :longstr, realm_name},
        {"x_astarte_device_id", :longstr, device_id},
        {"x_astarte_remote_ip", :longstr, ip}
      ]

      # message_id = "message#{System.unique_integer()}"
      # retry_all_policy = retry_all_policy() |> Enum.at(0)
      # retry_all_routing_key = generate_routing_key(realm_name, retry_all_policy.name)

      # "routing_key#{System.unique_integer()}"
      routing_key = Astarte.DataUpdaterPlant.AMQPTestHelper.events_routing_key()
      payload = "payload#{System.unique_integer()}"
      channel = "channel#{System.unique_integer()}"

      ExRabbitPool.with_channel(:events_consumer_pool, fn {:ok, chan} ->
        produce_event(channel, routing_key, payload, [], message_id)
      end)

      # meta = %{headers: headers, message_id: message_id, delivery_tag: delivery_tag, timestamp: timestamp}
      # send(pid, {:basic_deliver, payload, meta})
    end

    # test "routes disconnection messages to handle_disconnection", %{consumer: pid} do
    #   expect(DataUpdater, :handle_disconnection, fn realm, device_id, tracking_id, timestamp ->
    #     assert realm == "test_realm"
    #     assert device_id == "test_device"
    #     assert tracking_id == {"test_message_id", 2}
    #     assert timestamp == 1234567891
    #     :ok
    #   end)

    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "disconnection"},
    #     {"x_astarte_realm", :longstr, "test_realm"},
    #     {"x_astarte_device_id", :longstr, "test_device"}
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 2, timestamp: 1234567891}
    #   send(pid, {:basic_deliver, "test_payload", meta})
    # end

    # test "routes heartbeat messages to handle_heartbeat", %{consumer: pid} do
    #   expect(DataUpdater, :handle_heartbeat, fn realm, device_id, tracking_id, timestamp ->
    #     assert realm == "test_realm"
    #     assert device_id == "test_device"
    #     assert tracking_id == {"test_message_id", 3}
    #     assert timestamp == 1234567892
    #     :ok
    #   end)

    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "heartbeat"},
    #     {"x_astarte_realm", :longstr, "test_realm"},
    #     {"x_astarte_device_id", :longstr, "test_device"}
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 3, timestamp: 1234567892}
    #   send(pid, {:basic_deliver, "test_payload", meta})
    # end

    # test "routes internal messages to handle_internal", %{consumer: pid} do
    #   expect(DataUpdater, :handle_internal, fn realm, device_id, internal_path, payload, tracking_id, timestamp ->
    #     assert realm == "test_realm"
    #     assert device_id == "test_device"
    #     assert internal_path == "/test/path"
    #     assert payload == "test_payload"
    #     assert tracking_id == {"test_message_id", 4}
    #     assert timestamp == 1234567893
    #     :ok
    #   end)

    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "internal"},
    #     {"x_astarte_realm", :longstr, "test_realm"},
    #     {"x_astarte_device_id", :longstr, "test_device"},
    #     {"x_astarte_internal_path", :longstr, "/test/path"}
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 4, timestamp: 1234567893}
    #   send(pid, {:basic_deliver, "test_payload", meta})
    # end

    # test "routes introspection messages to handle_introspection", %{consumer: pid} do
    #   expect(DataUpdater, :handle_introspection, fn realm, device_id, payload, tracking_id, timestamp ->
    #     assert realm == "test_realm"
    #     assert device_id == "test_device"
    #     assert payload == "test_introspection"
    #     assert tracking_id == {"test_message_id", 5}
    #     assert timestamp == 1234567894
    #     :ok
    #   end)

    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "introspection"},
    #     {"x_astarte_realm", :longstr, "test_realm"},
    #     {"x_astarte_device_id", :longstr, "test_device"}
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 5, timestamp: 1234567894}
    #   send(pid, {:basic_deliver, "test_introspection", meta})
    # end

    # test "routes data messages to handle_data", %{consumer: pid} do
    #   expect(DataUpdater, :handle_data, fn realm, device_id, interface, path, payload, tracking_id, timestamp ->
    #     assert realm == "test_realm"
    #     assert device_id == "test_device"
    #     assert interface == "test_interface"
    #     assert path == "/test/path"
    #     assert payload == "test_payload"
    #     assert tracking_id == {"test_message_id", 6}
    #     assert timestamp == 1234567895
    #     :ok
    #   end)

    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "data"},
    #     {"x_astarte_realm", :longstr, "test_realm"},
    #     {"x_astarte_device_id", :longstr, "test_device"},
    #     {"x_astarte_interface", :longstr, "test_interface"},
    #     {"x_astarte_path", :longstr, "/test/path"}
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 6, timestamp: 1234567895}
    #   send(pid, {:basic_deliver, "test_payload", meta})
    # end

    # test "routes control messages to handle_control", %{consumer: pid} do
    #   expect(DataUpdater, :handle_control, fn realm, device_id, control_path, payload, tracking_id, timestamp ->
    #     assert realm == "test_realm"
    #     assert device_id == "test_device"
    #     assert control_path == "/test/path"
    #     assert payload == "test_payload"
    #     assert tracking_id == {"test_message_id", 7}
    #     assert timestamp == 1234567896
    #     :ok
    #   end)

    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "control"},
    #     {"x_astarte_realm", :longstr, "test_realm"},
    #     {"x_astarte_device_id", :longstr, "test_device"},
    #     {"x_astarte_control_path", :longstr, "/test/path"}
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 7, timestamp: 1234567896}
    #   send(pid, {:basic_deliver, "test_payload", meta})
    # end

    # test "returns :invalid_msg for unknown message types", %{consumer: pid} do
    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "unknown_type"},
    #     {"x_astarte_realm", :longstr, "test_realm"},
    #     {"x_astarte_device_id", :longstr, "test_device"}
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 8, timestamp: 1234567897}
    #   send(pid, {:basic_deliver, "test_payload", meta})
    # end

    # test "returns :invalid_msg when required headers are missing", %{consumer: pid} do
    #   headers = [
    #     {"x_astarte_msg_type", :longstr, "data"},
    #     {"x_astarte_device_id", :longstr, "test_device"}
    #     # Missing realm, interface, path
    #   ]
    #   meta = %{headers: headers, message_id: "test_message_id", delivery_tag: 9, timestamp: 1234567898}
    #   send(pid, {:basic_deliver, "test_payload", meta})
    # end
  end

  defp tracking_id do
    message_id = :erlang.unique_integer([:monotonic]) |> Integer.to_string()
    delivery_tag = :erlang.unique_integer([:monotonic])
    {message_id, delivery_tag}
  end

  defp insert_device_and_start_data_updater(realm_name, device_id, params \\ []) do
    encoded_device_id = Astarte.Core.Device.encode_device_id(device_id)
    Database.insert_device(device_id, realm_name, params)

    setup_data_updater(realm_name, encoded_device_id)
    :ok
  end

  defp produce_event(chan, routing_key, payload, headers, message_id) do
    AMQP.Basic.publish(chan, Config.events_exchange_name!(), routing_key, payload,
      headers: headers,
      message_id: message_id
    )
  end
end
