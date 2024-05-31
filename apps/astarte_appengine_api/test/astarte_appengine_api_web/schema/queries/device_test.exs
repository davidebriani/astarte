defmodule Astarte.AppEngine.APIWeb.Schema.Queries.DeviceTest do
  use Astarte.AppEngine.APIWeb.GraphqlCase, async: true

  describe "device query" do
    test "returns device if present", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          connected: true,
          last_connection: truncated_utc_now() |> DateTime.add(-1, :hour),
          last_disconnection: truncated_utc_now() |> DateTime.add(-3, :hour)
        )

      id = AshGraphql.Resource.encode_relay_id(fixture)

      device =
        device_query(tenant: realm, id: id)
        |> extract_result!()

      assert device["id"] == id
      assert device["deviceId"] == fixture.device_id
      assert device["connected"] == true
      assert device["lastConnection"] == fixture.last_connection |> DateTime.to_iso8601()
      assert device["lastDisconnection"] == fixture.last_disconnection |> DateTime.to_iso8601()
    end

    test "returns nil if non existing", %{realm: realm} do
      id = non_existing_device_id(realm)
      result = device_query(tenant: realm, id: id)
      assert %{data: %{"device" => nil}} = result
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
          attributes
        }
      }
      """

      device =
        device_query(document: document, tenant: realm, id: id)
        |> extract_result!()

      assert device["attributes"] == fixture.attributes
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
        device_query(tenant: realm, id: id)
        |> extract_result!()

      length(device["groups"]) == 2
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
          connected
          lastConnection
          lastDisconnection
          attributes
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
