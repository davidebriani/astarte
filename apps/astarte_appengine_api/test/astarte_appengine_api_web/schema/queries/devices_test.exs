defmodule Astarte.AppEngine.APIWeb.Schema.Queries.DevicesTest do
  use Astarte.AppEngine.APIWeb.GraphqlCase, async: true

  describe "devices query" do
    test "returns empty devices", %{realm: realm} do
      assert [] == devices_query(tenant: realm) |> extract_result!()
    end

    test "returns devices if present", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          connected: true,
          last_connection: truncated_utc_now() |> DateTime.add(-1, :hour),
          last_disconnection: truncated_utc_now() |> DateTime.add(-3, :hour)
        )

      assert [device] = devices_query(tenant: realm) |> extract_result!()

      assert device["id"] == AshGraphql.Resource.encode_relay_id(fixture)
      assert device["deviceId"] == fixture.device_id
      assert device["connected"] == true
      assert device["lastConnection"] == fixture.last_connection |> DateTime.to_iso8601()
      assert device["lastDisconnection"] == fixture.last_disconnection |> DateTime.to_iso8601()
    end
  end

  defp truncated_utc_now do
    DateTime.utc_now() |> DateTime.truncate(:millisecond)
  end

  defp devices_query(opts) do
    default_document =
      """
      query Devices($filter: DeviceFilterInput, $sort: [DeviceSortInput]) {
        devices(filter: $filter, sort: $sort) {
          id
          deviceId
          connected
          lastConnection
          lastDisconnection
        }
      }
      """

    {tenant, opts} = Keyword.pop!(opts, :tenant)
    document = Keyword.get(opts, :document, default_document)

    variables =
      %{
        "filter" => opts[:filter],
        "sort" => opts[:sort] || []
      }

    Absinthe.run!(document, Astarte.AppEngine.APIWeb.Schema,
      variables: variables,
      context: %{tenant: tenant}
    )
  end

  defp extract_result!(result) do
    assert %{data: %{"devices" => devices}} = result
    assert devices != nil
    refute :errors in Map.keys(result)

    devices
  end
end
