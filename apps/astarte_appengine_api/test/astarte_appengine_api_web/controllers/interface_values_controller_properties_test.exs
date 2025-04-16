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

defmodule Astarte.AppEngine.APIWeb.InterfaceValuesControllerPropertiesTest do
  use Astarte.AppEngine.API.DataCase
  use Astarte.AppEngine.APIWeb.ConnCase
  use ExUnitProperties

  alias Astarte.AppEngine.API.JWTTestHelper
  alias Astarte.Core.Generators
  alias Astarte.AppEngine.API.Device

  setup %{conn: conn} do
    authorized_conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "bearer #{JWTTestHelper.gen_jwt_all_access_token()}")

    {:ok, conn: authorized_conn}
  end

  describe "index" do
    test "lists all interfaces using a invalid device id", %{conn: conn, realm: realm} do
      conn =
        get(
          conn,
          interface_values_path(
            conn,
            :index,
            realm,
            "zzzzzzzzzzzf0VMRgIBAQAAAAAAAAAAAA"
          )
        )

      assert json_response(conn, 400)["errors"] == %{"detail" => "Bad request"}
    end

    property "lists all interfaces", %{conn: conn, realm: realm} do
      check all interfaces <- uniq_list_of(Generators.Interface.interface()),
                device <- Generators.Device.device(interfaces: interfaces) do
        insert_device!(realm, device)

        conn =
          get(
            conn,
            interface_values_path(
              conn,
              :index,
              realm,
              device.encoded_id
            )
          )

        interface_names = Enum.map(interfaces, & &1.name)

        assert Enum.sort(json_response(conn, 200)["data"]) == Enum.sort(interface_names)
      end
    end
  end

  describe "show" do
    property "returns empty map at root path for empty properties interface", %{
      conn: conn,
      realm: realm
    } do
      check all interfaces <-
                  uniq_list_of(
                    Generators.Interface.interface(
                      ownership: :server,
                      type: :properties,
                      aggregation: :individual
                    )
                  ),
                device <- Generators.Device.device(interfaces: interfaces) do
        insert_device!(realm, device)

        for interface <- interfaces do
          :ok = insert_interface!(realm, interface)
        end

        for interface <- interfaces do
          from_path_conn =
            get(
              conn,
              interface_values_path(
                conn,
                :show,
                realm,
                device.encoded_id,
                interface.name
              )
            )

          assert json_response(from_path_conn, 200)["data"] == %{}
        end
      end
    end

    property "returns value at specific path for properties interface", %{
      conn: conn,
      realm: realm
    } do
      check all interfaces <-
                  uniq_list_of(
                    Generators.Interface.interface(
                      ownership: :server,
                      type: :properties,
                      aggregation: :individual
                    )
                  ),
                device <- Generators.Device.device(interfaces: interfaces) do
        insert_device!(realm, device)

        for interface <- interfaces do
          :ok = insert_interface!(realm, interface)
        end

        for interface <- interfaces,
            mapping <- interface.mappings,
            param <- string(:ascii),
            value <- Generators.Value.value(mapping.value_type) do
          path = Regex.replace(~r/%\{[\{]+\}/, mapping.endpoint, param)
          path_tokens = String.split(path, "/")

          # TODO: seed value as interface data, for example with
          # Queries.insert_value_into_db

          from_path_conn =
            get(
              conn,
              interface_values_path(
                conn,
                :show,
                realm,
                device.encoded_id,
                interface.name,
                path_tokens
              )
            )

          assert json_response(from_path_conn, 200)["data"] == value
        end
      end
    end
  end

  describe "update" do
    property "publishes value for properties interface", %{conn: conn, realm: realm} do
      check all interfaces <-
                  uniq_list_of(
                    Generators.Interface.interface(
                      ownership: :server,
                      type: :properties,
                      aggregation: :individual
                    )
                  ),
                device <- Generators.Device.device(interfaces: interfaces) do
        insert_device!(realm, device)

        for interface <- interfaces do
          :ok = insert_interface!(realm, interface)
        end

        for interface <- interfaces,
            mapping <- interface.mappings,
            param <- string(:ascii),
            value <- Generators.Value.value(mapping.value_type) do
          path = Regex.replace(~r/%\{[\{]+\}/, mapping.endpoint, param)
          path_tokens = String.split(path, "/")

          # TODO: Use Mox to expect a call to MockRPCClient.rpc_call/2
          # and assert that the correct values are being published.

          from_path_conn =
            get(
              conn,
              interface_values_path(
                conn,
                :update,
                realm,
                device.encoded_id,
                interface.name,
                path_tokens
              )
            )

          assert json_response(from_path_conn, 200)["data"] == value
        end
      end
    end
  end
end
