Mix.install([
  {:astarte_device, github: "astarte-platform/astarte-device-sdk-elixir"},
  {:astarte_client, github: "astarte-platform/astarte-client-elixir"},
  {:jason, "~> 1.4"}
])

defmodule AstarteAPI do
  @interface_names [
    "test.datastreamIndividual.ExplicitTimestamp",
    "test.datastreamIndividual.Parametric",
    "test.datastreamIndividual.ServerOwned",
    "test.datastreamIndividual.Simple",
    "test.datastreamObject.ExplicitTimestamp",
    "test.datastreamObject.Parametric",
    "test.datastreamObject.ServerOwned",
    "test.datastreamObject.Simple",
    "test.propertiesIndividual.AllowUnset",
    "test.propertiesIndividual.Parametric",
    "test.propertiesIndividual.ServerOwned",
    "test.propertiesIndividual.Simple"
  ]

  @astarte_api_url "http://api.astarte.localhost/"
  @realm_name "test"

  @realm_private_key Path.dirname(__ENV__.file)
                     |> Path.join("../test_private.pem")
                     |> File.read!()

  alias Astarte.Client.{AppEngine, Pairing, RealmManagement}

  def sync_interfaces do
    Enum.each(interfaces(), fn interface ->
      :ok = install_interface(interface)
    end)

    :ok
  end

  defp interfaces do
    Enum.map(@interface_names, fn interface_name ->
      Path.dirname(__ENV__.file)
      |> Path.join("interfaces/#{interface_name}.json")
      |> File.read!()
      |> Jason.decode!()
    end)
  end

  defp install_interface(interface) do
    rm_client = realm_management_client!()
    interface_name = interface["interface_name"]
    interface_major = interface["version_major"]

    case RealmManagement.Interfaces.get(rm_client, interface_name, interface_major) do
      {:ok, _data} ->
        :ok

      {:error, _reason} ->
        with {:ok, _data} <- RealmManagement.Interfaces.create(rm_client, interface) do
          :ok
        end
    end
  end

  def register_device(device_id) do
    p_client = pairing_client!()

    if device_exists?(device_id) do
      :ok = Pairing.Agent.unregister(p_client, device_id)
    end

    data = %{
      "hw_id" => device_id,
      "initial_introspection" => %{}
    }

    {:ok, result} = Pairing.Agent.register(p_client, data)

    credentials_secret = result["data"]["credentials_secret"]

    {:ok, credentials_secret}
  end

  def get_datastream_data(device_id, interface_name, opts \\ []) do
    a_client = appengine_client!()

    AppEngine.Devices.get_datastream_data(a_client, device_id, interface_name, opts)
  end

  def send_datastream(device_id, interface_name, path, data) do
    a_client = appengine_client!()

    AppEngine.Devices.send_datastream(a_client, device_id, interface_name, path, data)
    :timer.sleep(500)
  end

  def get_properties_data(device_id, interface_name, opts \\ []) do
    a_client = appengine_client!()

    AppEngine.Devices.get_properties_data(a_client, device_id, interface_name, opts)
  end

  def set_property(device_id, interface_name, path, data) do
    a_client = appengine_client!()

    AppEngine.Devices.set_property(a_client, device_id, interface_name, path, data)
    :timer.sleep(500)
  end

  defp device_exists?(device_id) do
    a_client = appengine_client!()

    case AppEngine.Devices.get_device_status(a_client, device_id) do
      {:ok, _data} -> true
      {:error, _reason} -> false
    end
  end

  defp appengine_client!() do
    {:ok, a_client} =
      AppEngine.new(
        @astarte_api_url,
        @realm_name,
        private_key: @realm_private_key
      )

    a_client
  end

  defp realm_management_client!() do
    {:ok, rm_client} =
      RealmManagement.new(
        @astarte_api_url,
        @realm_name,
        private_key: @realm_private_key
      )

    rm_client
  end

  defp pairing_client!() do
    {:ok, p_client} =
      Pairing.new(
        @astarte_api_url,
        @realm_name,
        private_key: @realm_private_key
      )

    p_client
  end
end

defmodule AstarteDevice do
  @pairing_url "http://api.astarte.localhost/pairing"
  @realm_name "test"

  alias Astarte.Device

  def send_datastream(device_pid, interface_name, path, value, opts \\ []) do
    :ok = Device.send_datastream(device_pid, interface_name, path, value, opts)
    :timer.sleep(500)
    :ok
  end

  def set_property(device_pid, interface_name, path, value) do
    :ok = Device.set_property(device_pid, interface_name, path, value)
    :timer.sleep(500)
    :ok
  end

  def unset_property(device_pid, interface_name, path) do
    :ok = Device.unset_property(device_pid, interface_name, path)
    :timer.sleep(500)
    :ok
  end

  def start_device!(device_id, credentials_secret) do
    {:ok, device_pid} =
      Device.start_link(
        pairing_url: @pairing_url,
        realm: @realm_name,
        device_id: device_id,
        credentials_secret: credentials_secret,
        interface_provider: "./interfaces",
        ignore_ssl_errors: true
      )

    :ok = Device.wait_for_connection(device_pid)

    device_pid
  end

  def stop_device!(device_pid) do
    :gen_statem.stop(device_pid)
  end
end

ExUnit.start()

defmodule AssertionTest do
  use ExUnit.Case, async: false

  @device_id "YHjKs3SMTgqq09eD7fzm6w"
  @sample_values %{
    "binaryblob" => "YmluYXJ5YmxvYg==",
    "binaryblobarray" => ["YmluYXJ5YmxvYmFycmF5MQ==","YmluYXJ5YmxvYmFycmF5Mg=="],
    "boolean" => true,
    "booleanarray" => [true, false],
    "datetime" => 0,
    "datetimearray" => [0, 40_271_111],
    "double" => 1.1,
    "doublearray" => [1.1, 2.2],
    "integer" => 1,
    "integerarray" => [1, 2],
    "longinteger" => 1,
    "longintegerarray" => [1, 2],
    "string" => "string",
    "stringarray" => ["string1", "string2"]
  }

  setup_all do
    :ok = AstarteAPI.sync_interfaces()
    {:ok, credentials_secret} = AstarteAPI.register_device(@device_id)
    device_pid = AstarteDevice.start_device!(@device_id, credentials_secret)

    [device_pid: device_pid]
  end

  describe "test.datastreamIndividual.ExplicitTimestamp" do
    @interface "test.datastreamIndividual.ExplicitTimestamp"

    test "returns all latest values when querying the root path", %{device_pid: device_pid} do
      Enum.each(@sample_values, fn {type, value} ->
        :ok = AstarteDevice.send_datastream(device_pid, @interface, "/#{type}", value)
      end)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                 "binaryblob" => %{
                   "value" => "WW1sdVlYSjVZbXh2WWc9PQ=="
                 },
                 "binaryblobarray" => %{
                   "value" => ["WW1sdVlYSjVZbXh2WW1GeWNtRjVNUT09", "WW1sdVlYSjVZbXh2WW1GeWNtRjVNZz09"]
                 },
                 "boolean" => %{
                   "value" => true
                 },
                 "booleanarray" => %{
                   "value" => [true, false]
                 },
                 "datetime" => %{
                   "value" => "1970-01-01T00:00:00.000Z"
                 },
                 "datetimearray" => %{
                   "value" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"]
                 },
                 "double" => %{
                   "value" => 1.1
                 },
                 "doublearray" => %{
                   "value" => [1.1, 2.2]
                 },
                 "integer" => %{
                   "value" => 1
                 },
                 "integerarray" => %{
                   "value" => [1, 2]
                 },
                 "string" => %{
                   "value" => "string"
                 },
                 "stringarray" => %{
                   "value" => ["string1", "string2"]
                 }
               }
             } = result
    end

    test "returns string timestamp and reception_timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                 "double" => %{
                   "reception_timestamp" => timestamp,
                   "timestamp" => timestamp,
                   "value" => 1.1
                 }
               }
             } = result

      assert String.valid?(timestamp)
    end

    test "returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
               "data" => %{
                 "double" => %{
                   "reception_timestamp" => timestamp,
                   "timestamp" => timestamp,
                   "value" => 1.1
                 }
               }
             } = result

      assert is_integer(timestamp)
    end

    test "returns the specified timestamp when querying the root path", %{device_pid: device_pid} do
      datetime = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1, timestamp: datetime)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
        "data" => %{
          "double" => %{
            "reception_timestamp" => _reception_timestamp,
            "timestamp" => timestamp,
            "value" => 1.1
          }
        }
      } = result

      assert {:ok, ^datetime, _} = DateTime.from_iso8601(timestamp)
    end

    test "does not return the reception_timestamp when querying a specific path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the specified timestamp when querying a specific path", %{device_pid: device_pid} do
      datetime = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1, timestamp: datetime)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{
        "timestamp" => timestamp,
        "value" => 1.1
      } = List.last(result["data"])

      assert {:ok, ^datetime, _} = DateTime.from_iso8601(timestamp)
    end

    test "returns the history of values when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 2.2)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => values} = result

      assert [
               %{
                 "timestamp" => timestamp1,
                 "value" => 2.2
               },
               %{
                 "timestamp" => timestamp2,
                 "value" => 1.1
               }
               | _
             ] = Enum.reverse(values)

      assert String.valid?(timestamp1)
      assert String.valid?(timestamp2)
    end
  end

  describe "test.datastreamIndividual.Parametric" do
    @interface "test.datastreamIndividual.Parametric"

    test "returns all latest values when querying the root path", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/param1", 1.1)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/param2", 2.2)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                 "param1" => %{
                   "value" => 1.1
                 },
                 "param2" => %{
                   "value" => 2.2
                 }
               }
             } = result
    end

    test "returns string timestamp and reception_timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/param1", 1.1)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/param2", 2.2)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                 "param1" => %{
                   "reception_timestamp" => timestamp1,
                   "timestamp" => timestamp1,
                   "value" => 1.1
                 },
                 "param2" => %{
                   "reception_timestamp" => timestamp2,
                   "timestamp" => timestamp2,
                   "value" => 2.2
                 }
               }
             } = result

      assert String.valid?(timestamp1)
      assert String.valid?(timestamp2)
    end

    test "returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
               "data" => %{
                 "double" => %{
                   "reception_timestamp" => timestamp,
                   "timestamp" => timestamp,
                   "value" => 1.1
                 }
               }
             } = result

      assert is_integer(timestamp)
    end

    test "does not return the reception_timestamp when querying a specific path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the history of values when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 2.2)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => values} = result

      assert [
               %{
                 "timestamp" => timestamp1,
                 "value" => 2.2
               },
               %{
                 "timestamp" => timestamp2,
                 "value" => 1.1
               }
               | _
             ] = Enum.reverse(values)

      assert String.valid?(timestamp1)
      assert String.valid?(timestamp2)
    end
  end

  describe "test.datastreamIndividual.ServerOwned" do
    @interface "test.datastreamIndividual.ServerOwned"

    test "returns all latest values when querying the root path" do
      Enum.each(@sample_values, fn {type, value} ->
        :ok = AstarteAPI.send_datastream(@device_id, @interface, "/#{type}", value)
      end)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
        "data" => %{
          "binaryblob" => %{
            "value" => "YmluYXJ5YmxvYg=="
          },
          "binaryblobarray" => %{
            "value" => ["YmluYXJ5YmxvYmFycmF5MQ==", "YmluYXJ5YmxvYmFycmF5Mg=="]
          },
          "boolean" => %{
            "value" => true
          },
          "booleanarray" => %{
            "value" => [true, false]
          },
          "datetime" => %{
            "value" => "1970-01-01T00:00:00.000Z"
          },
          "datetimearray" => %{
            "value" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"]
          },
          "double" => %{
            "value" => 1.1
          },
          "doublearray" => %{
            "value" => [1.1, 2.2]
          },
          "integer" => %{
            "value" => 1
          },
          "integerarray" => %{
            "value" => [1, 2]
          },
          "string" => %{
            "value" => "string"
          },
          "stringarray" => %{
            "value" => ["string1", "string2"]
          }
        }
      } = result
    end

    test "returns string timestamp and reception_timestamp when querying the root path" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                 "double" => %{
                   "reception_timestamp" => timestamp1,
                   "timestamp" => timestamp1,
                   "value" => 1.1
                 },
               }
             } = result

      assert String.valid?(timestamp1)
    end

    test "returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
               "data" => %{
                 "double" => %{
                   "reception_timestamp" => timestamp,
                   "timestamp" => timestamp,
                   "value" => 1.1
                 }
               }
             } = result

      assert is_integer(timestamp)
    end

    test "does not return the reception_timestamp when querying a specific path" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the history of values when querying a specific path" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/double", 1.1)
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/double", 2.2)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => values} = result

      assert [
               %{
                 "timestamp" => timestamp1,
                 "value" => 2.2
               },
               %{
                 "timestamp" => timestamp2,
                 "value" => 1.1
               }
               | _
             ] = Enum.reverse(values)

      assert String.valid?(timestamp1)
      assert String.valid?(timestamp2)
    end
  end

  describe "test.datastreamIndividual.Simple" do
    @interface "test.datastreamIndividual.Simple"

    test "returns all latest values when querying the root path", %{device_pid: device_pid} do
      Enum.each(@sample_values, fn {type, value} ->
        :ok = AstarteDevice.send_datastream(device_pid, @interface, "/#{type}", value)
      end)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
        "data" => %{
          "binaryblob" => %{
            "value" => "WW1sdVlYSjVZbXh2WWc9PQ=="
          },
          "binaryblobarray" => %{
            "value" => ["WW1sdVlYSjVZbXh2WW1GeWNtRjVNUT09", "WW1sdVlYSjVZbXh2WW1GeWNtRjVNZz09"]
          },
          "boolean" => %{
            "value" => true
          },
          "booleanarray" => %{
            "value" => [true, false]
          },
          "datetime" => %{
            "value" => "1970-01-01T00:00:00.000Z"
          },
          "datetimearray" => %{
            "value" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"]
          },
          "double" => %{
            "value" => 1.1
          },
          "doublearray" => %{
            "value" => [1.1, 2.2]
          },
          "integer" => %{
            "value" => 1
          },
          "integerarray" => %{
            "value" => [1, 2]
          },
          "string" => %{
            "value" => "string"
          },
          "stringarray" => %{
            "value" => ["string1", "string2"]
          }
        }
      } = result
    end

    test "returns string timestamp and reception_timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/integer", 1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                 "double" => %{
                   "reception_timestamp" => timestamp1,
                   "timestamp" => timestamp1,
                   "value" => 1.1
                 },
                 "integer" => %{
                   "reception_timestamp" => timestamp2,
                   "timestamp" => timestamp2,
                   "value" => 1
                 }
               }
             } = result

      assert String.valid?(timestamp1)
      assert String.valid?(timestamp2)
    end

    test "returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
               "data" => %{
                 "double" => %{
                   "reception_timestamp" => timestamp,
                   "timestamp" => timestamp,
                   "value" => 1.1
                 }
               }
             } = result

      assert is_integer(timestamp)
    end

    test "does not return the reception_timestamp when querying a specific path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the history of values when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 1.1)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/double", 2.2)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/double")

      %{"data" => values} = result

      assert [
               %{
                 "timestamp" => timestamp1,
                 "value" => 2.2
               },
               %{
                 "timestamp" => timestamp2,
                 "value" => 1.1
               }
               | _
             ] = Enum.reverse(values)

      assert String.valid?(timestamp1)
      assert String.valid?(timestamp2)
    end
  end

  describe "test.datastreamObject.ExplicitTimestamp" do
    @interface "test.datastreamObject.ExplicitTimestamp"

    test "returns all latest values when querying the root path", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      assert %{
        "binaryblob" => "WW1sdVlYSjVZbXh2WWc9PQ==",
        "binaryblobarray" => ["WW1sdVlYSjVZbXh2WW1GeWNtRjVNUT09", "WW1sdVlYSjVZbXh2WW1GeWNtRjVNZz09"],
        "boolean" => true,
        "booleanarray" => [true, false],
        "datetime" => "1970-01-01T00:00:00.000Z",
        "datetimearray" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"],
        "double" => 1.1,
        "doublearray" => [1.1, 2.2],
        "integer" => 1,
        "integerarray" => [1, 2],
        "string" => "string",
        "stringarray" => ["string1", "string2"]
       } = List.last(values)
    end

    test "returns string timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result
      assert %{"timestamp" => timestamp} = List.last(values)
      assert String.valid?(timestamp)
    end

    test "returns numeric timestamp when querying the root path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
        "data" => %{
         "object" => values
        }
      } = result
      assert %{"timestamp" => timestamp} = List.last(values)

      assert is_integer(timestamp)
    end

    test "does not return a reception_timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      value = List.last(values)

      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns the specified timestamp when querying the root path", %{device_pid: device_pid} do
      datetime = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values, timestamp: datetime)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      %{
        "data" => %{
         "object" => values
        }
      } = result

      %{"timestamp" => timestamp} = List.last(values)

      assert {:ok, ^datetime, _} = DateTime.from_iso8601(timestamp)
    end

    test "does not return the reception_timestamp when querying a specific object", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the specified timestamp when querying a specific object", %{device_pid: device_pid} do
      datetime = DateTime.utc_now() |> DateTime.truncate(:millisecond)
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values, timestamp: datetime)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{
        "timestamp" => timestamp,
      } = List.last(result["data"])

      assert {:ok, ^datetime, _} = DateTime.from_iso8601(timestamp)
    end

    test "returns the history of values when querying a specific object", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", %{"double" => 1.1})
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", %{"double" => 2.2})

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => values} = result

      assert [%{"double" => 2.2}, %{"double" => 1.1} | _] = Enum.reverse(values)
    end
  end

  describe "test.datastreamObject.Parametric" do
    @interface "test.datastreamObject.Parametric"

    test "returns all latest values when querying the root path", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      assert %{
        "binaryblob" => "WW1sdVlYSjVZbXh2WWc9PQ==",
        "binaryblobarray" => ["WW1sdVlYSjVZbXh2WW1GeWNtRjVNUT09", "WW1sdVlYSjVZbXh2WW1GeWNtRjVNZz09"],
        "boolean" => true,
        "booleanarray" => [true, false],
        "datetime" => "1970-01-01T00:00:00.000Z",
        "datetimearray" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"],
        "double" => 1.1,
        "doublearray" => [1.1, 2.2],
        "integer" => 1,
        "integerarray" => [1, 2],
        "string" => "string",
        "stringarray" => ["string1", "string2"]
       } = List.last(values)
    end

    test "returns string timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result
      assert %{"timestamp" => timestamp} = List.last(values)
      assert String.valid?(timestamp)
    end

    test "returns numeric timestamp when querying the root path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
        "data" => %{
         "object" => values
        }
      } = result
      assert %{"timestamp" => timestamp} = List.last(values)

      assert is_integer(timestamp)
    end

    test "does not return a reception_timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      value = List.last(values)

      refute Map.has_key?(value, "reception_timestamp")
    end

    test "does not return the reception_timestamp when querying a specific object", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the history of values when querying a specific object", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", %{"double" => 1.1})
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", %{"double" => 2.2})

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => values} = result

      assert [%{"double" => 2.2}, %{"double" => 1.1} | _] = Enum.reverse(values)
    end
  end

  describe "test.datastreamObject.ServerOwned" do
    @interface "test.datastreamObject.ServerOwned"

    test "returns all latest values when querying the root path" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      assert %{
        "binaryblob" => "YmluYXJ5YmxvYg==",
        "binaryblobarray" => ["YmluYXJ5YmxvYmFycmF5MQ==", "YmluYXJ5YmxvYmFycmF5Mg=="],
        "boolean" => true,
        "booleanarray" => [true, false],
        "datetime" => "1970-01-01T00:00:00.000Z",
        "datetimearray" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"],
        "double" => 1.1,
        "doublearray" => [1.1, 2.2],
        "integer" => 1,
        "integerarray" => [1, 2],
        "string" => "string",
        "stringarray" => ["string1", "string2"]
       } = List.last(values)
    end

    test "returns string timestamp when querying the root path" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result
      assert %{"timestamp" => timestamp} = List.last(values)
      assert String.valid?(timestamp)
    end

    test "returns numeric timestamp when querying the root path with keep_milliseconds" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
        "data" => %{
         "object" => values
        }
      } = result
      assert %{"timestamp" => timestamp} = List.last(values)
      assert is_integer(timestamp)
    end

    test "does not return a reception_timestamp when querying the root path" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      value = List.last(values)

      refute Map.has_key?(value, "reception_timestamp")
    end

    test "does not return the reception_timestamp when querying a specific object" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the history of values when querying a specific object" do
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", %{"double" => 1.1})
      :ok = AstarteAPI.send_datastream(@device_id, @interface, "/object", %{"double" => 2.2})

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => values} = result

      assert [%{"double" => 2.2}, %{"double" => 1.1} | _] = Enum.reverse(values)
    end
  end

  describe "test.datastreamObject.Simple" do
    @interface "test.datastreamObject.Simple"

    test "returns all latest values when querying the root path", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      assert %{
        "binaryblob" => "WW1sdVlYSjVZbXh2WWc9PQ==",
        "binaryblobarray" => ["WW1sdVlYSjVZbXh2WW1GeWNtRjVNUT09", "WW1sdVlYSjVZbXh2WW1GeWNtRjVNZz09"],
        "boolean" => true,
        "booleanarray" => [true, false],
        "datetime" => "1970-01-01T00:00:00.000Z",
        "datetimearray" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"],
        "double" => 1.1,
        "doublearray" => [1.1, 2.2],
        "integer" => 1,
        "integerarray" => [1, 2],
        "string" => "string",
        "stringarray" => ["string1", "string2"]
       } = List.last(values)
    end

    test "returns string timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result
      assert %{"timestamp" => timestamp} = List.last(values)
      assert String.valid?(timestamp)
    end

    test "returns numeric timestamp when querying the root path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, query: [keep_milliseconds: true])

      assert %{
        "data" => %{
         "object" => values
        }
      } = result
      assert %{"timestamp" => timestamp} = List.last(values)

      assert is_integer(timestamp)
    end

    test "does not return a reception_timestamp when querying the root path", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface)

      assert %{
               "data" => %{
                "object" => values
               }
             } = result

      value = List.last(values)

      refute Map.has_key?(value, "reception_timestamp")
    end

    test "does not return the reception_timestamp when querying a specific object", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      refute Map.has_key?(value, "reception_timestamp")
    end

    test "returns numeric timestamp when querying a specific path with keep_milliseconds", %{
      device_pid: device_pid
    } do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", @sample_values)

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object", query: [keep_milliseconds: true])

      %{"data" => [value | _]} = result

      assert Map.has_key?(value, "timestamp")
      assert is_integer(value["timestamp"])
    end

    test "returns the history of values when querying a specific object", %{device_pid: device_pid} do
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", %{"double" => 1.1})
      :ok = AstarteDevice.send_datastream(device_pid, @interface, "/object", %{"double" => 2.2})

      {:ok, result} = AstarteAPI.get_datastream_data(@device_id, @interface, path: "/object")

      %{"data" => values} = result

      assert [%{"double" => 2.2}, %{"double" => 1.1} | _] = Enum.reverse(values)
    end
  end

  describe "test.propertiesIndividual.AllowUnset" do
    @interface "test.propertiesIndividual.AllowUnset"

    test "returns all the properties when querying the root path", %{device_pid: device_pid} do
      Enum.each(@sample_values, fn {type, value} ->
        :ok = AstarteDevice.set_property(device_pid, @interface, "/#{type}", value)
      end)

      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      assert %{"data" => %{
        "binaryblob" => "WW1sdVlYSjVZbXh2WWc9PQ==",
        "binaryblobarray" => ["WW1sdVlYSjVZbXh2WW1GeWNtRjVNUT09", "WW1sdVlYSjVZbXh2WW1GeWNtRjVNZz09"],
        "boolean" => true,
        "booleanarray" => [true, false],
        "datetime" => "1970-01-01T00:00:00.000Z",
        "datetimearray" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"],
        "double" => 1.1,
        "doublearray" => [1.1, 2.2],
        "integer" => 1,
        "integerarray" => [1, 2],
        "string" => "string",
        "stringarray" => ["string1", "string2"]
      }} = result
    end

    test "does not return a property where nil was published when querying the root path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", 1.1)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      assert Map.has_key?(result["data"], "double")

      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", nil)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      refute Map.has_key?(result["data"], "double")
    end

    test "does not return a property that was deleted when querying the root path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", 1.1)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      assert Map.has_key?(result["data"], "double")

      :ok = AstarteDevice.unset_property(device_pid, @interface, "/double")
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      refute Map.has_key?(result["data"], "double")
    end

    test "returns the single value when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", 1.1)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface, path: "/double")

      assert %{
        "data" => 1.1
      } = result
    end

    test "if nil was published, returns empty map when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", 1.1)
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", nil)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface, path: "/double")

      assert result["data"] == %{}
    end

    test "returns empty map instead of a value if the property was deleted when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", 1.1)
      :ok = AstarteDevice.unset_property(device_pid, @interface, "/double")
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface, path: "/double")

      assert result["data"] == %{}
    end
  end

  describe "test.propertiesIndividual.Parametric" do
    @interface "test.propertiesIndividual.Parametric"

    test "returns all the properties when querying the root path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/param1", 1.1)
      :ok = AstarteDevice.set_property(device_pid, @interface, "/param2", 2.2)

      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      assert %{"data" => %{
        "param1" => 1.1,
        "param2" => 2.2
      }} = result
    end

    test "returns the single value when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", 1.1)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface, path: "/double")

      assert %{
        "data" => 1.1
      } = result
    end
  end

  describe "test.propertiesIndividual.ServerOwned" do
    @interface "test.propertiesIndividual.ServerOwned"

    test "returns all the properties when querying the root path" do
      Enum.each(@sample_values, fn {type, value} ->
        :ok = AstarteAPI.set_property(@device_id, @interface, "/#{type}", value)
      end)

      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      assert %{"data" => %{
        "binaryblob" => "YmluYXJ5YmxvYg==",
        "binaryblobarray" => ["YmluYXJ5YmxvYmFycmF5MQ==", "YmluYXJ5YmxvYmFycmF5Mg=="],
        "boolean" => true,
        "booleanarray" => [true, false],
        "datetime" => "1970-01-01T00:00:00.000Z",
        "datetimearray" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"],
        "double" => 1.1,
        "doublearray" => [1.1, 2.2],
        "integer" => 1,
        "integerarray" => [1, 2],
        "string" => "string",
        "stringarray" => ["string1", "string2"]
      }} = result
    end

    test "returns the single value when querying a specific path" do
      :ok = AstarteAPI.set_property(@device_id, @interface, "/double", 1.1)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface, path: "/double")

      assert %{
        "data" => 1.1
      } = result
    end
  end

  describe "test.propertiesIndividual.Simple" do
    @interface "test.propertiesIndividual.Simple"

    test "returns all the properties when querying the root path", %{device_pid: device_pid} do
      Enum.each(@sample_values, fn {type, value} ->
        :ok = AstarteDevice.set_property(device_pid, @interface, "/#{type}", value)
      end)

      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface)

      assert %{"data" => %{
        "binaryblob" => "WW1sdVlYSjVZbXh2WWc9PQ==",
        "binaryblobarray" => ["WW1sdVlYSjVZbXh2WW1GeWNtRjVNUT09", "WW1sdVlYSjVZbXh2WW1GeWNtRjVNZz09"],
        "boolean" => true,
        "booleanarray" => [true, false],
        "datetime" => "1970-01-01T00:00:00.000Z",
        "datetimearray" => ["1970-01-01T00:00:00.000Z", "1970-01-01T11:11:11.111Z"],
        "double" => 1.1,
        "doublearray" => [1.1, 2.2],
        "integer" => 1,
        "integerarray" => [1, 2],
        "string" => "string",
        "stringarray" => ["string1", "string2"]
      }} = result
    end

    test "returns the single value when querying a specific path", %{device_pid: device_pid} do
      :ok = AstarteDevice.set_property(device_pid, @interface, "/double", 1.1)
      {:ok, result} = AstarteAPI.get_properties_data(@device_id, @interface, path: "/double")

      assert %{
        "data" => 1.1
      } = result
    end
  end
end
