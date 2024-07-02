defmodule Astarte.AppEngine.APIWeb.Schema.Queries.DeviceTest do
  use Astarte.AppEngine.APIWeb.GraphqlCase, async: true

  alias Astarte.AppEngine.API.Devices

  describe "device query" do
    test "returns device if present", %{realm: realm} do
      fixture = device_fixture(tenant: realm)

      id = AshGraphql.Resource.encode_relay_id(fixture)

      device = device_query(tenant: realm, id: id) |> extract_result!()

      assert device["id"] == id
      assert device["deviceId"] == fixture.device_id
    end

    test "returns nil if non existing", %{realm: realm} do
      id = non_existing_device_id(realm)
      result = device_query(tenant: realm, id: id)
      assert %{data: %{"device" => nil}} = result
    end

    test "returns connection details", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          connected: true,
          last_connection: truncated_utc_now() |> DateTime.add(-1, :hour),
          last_disconnection: truncated_utc_now() |> DateTime.add(-3, :hour),
          first_credentials_request: truncated_utc_now() |> DateTime.add(-5, :hour),
          last_credentials_request_ip: "192.168.1.2",
          last_seen_ip: "192.168.1.2"
        )

      id = AshGraphql.Resource.encode_relay_id(fixture)

      document = """
      query Device($id: ID!) {
        device(id: $id) {
          id
          connected
          lastConnection
          lastDisconnection
          firstCredentialsRequest
          lastCredentialsRequestIp
          lastSeenIp
        }
      }
      """

      device =
        device_query(document: document, tenant: realm, id: id)
        |> extract_result!()

      assert device["connected"] == true
      assert device["lastConnection"] == fixture.last_connection |> DateTime.to_iso8601()
      assert device["lastDisconnection"] == fixture.last_disconnection |> DateTime.to_iso8601()

      assert device["firstCredentialsRequest"] ==
               fixture.first_credentials_request |> DateTime.to_iso8601()

      assert device["lastCredentialsRequestIp"] == "192.168.1.2"
      assert device["lastSeenIp"] == "192.168.1.2"
    end

    test "returns registration details", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          first_registration: truncated_utc_now()
        )

      id = AshGraphql.Resource.encode_relay_id(fixture)

      document = """
      query Device($id: ID!) {
        device(id: $id) {
          id
          firstRegistration
        }
      }
      """

      device =
        device_query(document: document, tenant: realm, id: id)
        |> extract_result!()

      assert device["firstRegistration"] == fixture.first_registration |> DateTime.to_iso8601()
    end

    test "returns attributes", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          attributes: %{"foo" => "bar", "beep" => "boop"}
        )

      id = AshGraphql.Resource.encode_relay_id(fixture)

      document = """
      query Device($id: ID!) {
        device(id: $id) {
          id
          attributes
        }
      }
      """

      device =
        device_query(document: document, tenant: realm, id: id)
        |> extract_result!()

      assert device["attributes"] == %{"foo" => "bar", "beep" => "boop"}
    end

    test "returns aliases", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          aliases: %{"foo" => "bar", "beep" => "boop"}
        )

      id = AshGraphql.Resource.encode_relay_id(fixture)

      document = """
      query Device($id: ID!) {
        device(id: $id) {
          id
          aliases
        }
      }
      """

      device =
        device_query(document: document, tenant: realm, id: id)
        |> extract_result!()

      assert device["aliases"] == %{"foo" => "bar", "beep" => "boop"}
    end

    test "returns groups", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          groups: %{
            "foo" => "b43ba208-1f69-11ef-9262-0242ac120002",
            "bar" => "c25c4b44-1f69-11ef-9262-0242ac120002"
          }
        )

      id = AshGraphql.Resource.encode_relay_id(fixture)

      document = """
      query Device($id: ID!) {
        device(id: $id) {
          id
          groups
        }
      }
      """

      device =
        device_query(document: document, tenant: realm, id: id)
        |> extract_result!()

      assert length(device["groups"]) == 2
      assert "foo" in device["groups"]
      assert "bar" in device["groups"]
    end
  end

  defp non_existing_device_id(tenant) do
    fixture = device_fixture(tenant: tenant)
    id = AshGraphql.Resource.encode_relay_id(fixture)
    :ok = Ash.destroy!(fixture)

    id
  end

  defp truncated_utc_now do
    DateTime.utc_now() |> DateTime.truncate(:millisecond)
  end

  defp device_query(opts) do
    default_document =
      """
      query Device($id: ID!) {
        device(id: $id) {
          id
          deviceId
        }
      }
      """

    tenant = Keyword.fetch!(opts, :tenant)
    id = Keyword.fetch!(opts, :id)

    variables = %{"id" => id}

    document = Keyword.get(opts, :document, default_document)

    Absinthe.run!(document, Astarte.AppEngine.APIWeb.Schema,
      variables: variables,
      context: %{tenant: tenant}
    )
  end

  defp extract_result!(result) do
    assert %{data: %{"device" => device}} = result
    assert device != nil
    refute :errors in Map.keys(result)

    device
  end
end
