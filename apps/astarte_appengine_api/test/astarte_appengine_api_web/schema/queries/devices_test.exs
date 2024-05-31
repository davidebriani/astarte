defmodule Astarte.AppEngine.APIWeb.Schema.Queries.DevicesTest do
  use Astarte.AppEngine.APIWeb.GraphqlCase, async: true

  describe "devices query" do
    test "returns empty devices", %{realm: realm} do
      assert %{"edges" => []} = devices_query(tenant: realm) |> extract_result!()
    end

    test "returns devices if present", %{realm: realm} do
      fixture =
        device_fixture(
          tenant: realm,
          connected: true,
          last_connection: truncated_utc_now() |> DateTime.add(-1, :hour),
          last_disconnection: truncated_utc_now() |> DateTime.add(-3, :hour),
          attributes: %{"foo" => "bar"}
        )

      assert %{"edges" => [%{"node" => device}]} =
               devices_query(tenant: realm) |> extract_result!()

      assert device["id"] == AshGraphql.Resource.encode_relay_id(fixture)
      assert device["deviceId"] == fixture.device_id
      assert device["connected"] == true
      assert device["lastConnection"] == fixture.last_connection |> DateTime.to_iso8601()
      assert device["lastDisconnection"] == fixture.last_disconnection |> DateTime.to_iso8601()
      assert device["attributes"] == %{"foo" => "bar"}
    end

    test "can paginate forward", %{realm: realm} do
      fixture_1 = device_fixture(tenant: realm)
      fixture_2 = device_fixture(tenant: realm)
      fixture_3 = device_fixture(tenant: realm)

      # We currently can't guarantee a specific sort when paginating, so we have to
      # do checks so they are independent from the sort order

      device_ids = [fixture_1.device_id, fixture_2.device_id, fixture_3.device_id]

      assert %{
               "edges" => [
                 %{"node" => device_1, "cursor" => after_device_1_cursor},
                 %{"node" => device_2}
               ],
               "pageInfo" => %{"hasNextPage" => true}
             } = devices_query(tenant: realm, first: 2) |> extract_result!()

      assert device_1["deviceId"] in device_ids
      assert device_2["deviceId"] in device_ids

      assert %{
               "edges" => [%{"node" => ^device_2}, %{"node" => device_3}],
               "pageInfo" => %{"hasNextPage" => false}
             } =
               devices_query(tenant: realm, first: 2, after: after_device_1_cursor)
               |> extract_result!()

      assert device_3["deviceId"] in device_ids

      assert device_1["deviceId"] != device_2["deviceId"]
      assert device_2["deviceId"] != device_3["deviceId"]
      assert device_3["deviceId"] != device_1["deviceId"]
    end

    test "can filter with equality", %{realm: realm} do
      online_fixture = device_fixture(tenant: realm, connected: true)
      _offline_fixture = device_fixture(tenant: realm, connected: false)

      filter = %{"connected" => %{"eq" => true}}

      assert %{"edges" => [%{"node" => device}]} =
               devices_query(tenant: realm, filter: filter)
               |> extract_result!()

      assert device["deviceId"] == online_fixture.device_id
    end

    test "can filter with comparison", %{realm: realm} do
      recently_connected_fixture =
        device_fixture(tenant: realm, last_connection: truncated_utc_now())

      two_days_ago = truncated_utc_now() |> DateTime.add(-48, :hour)

      _not_recently_connected_fixture =
        device_fixture(tenant: realm, last_connection: two_days_ago)

      one_day_ago =
        truncated_utc_now()
        |> DateTime.add(-24, :hour)
        |> DateTime.to_iso8601()

      filter = %{"lastConnection" => %{"greater_than" => one_day_ago}}

      assert %{"edges" => [%{"node" => device}]} =
               devices_query(tenant: realm, filter: filter)
               |> extract_result!()

      assert device["deviceId"] == recently_connected_fixture.device_id
    end

    test "can combine filters", %{realm: realm} do
      device_fixture(tenant: realm, total_received_msgs: 1, total_received_bytes: 100)
      device_fixture(tenant: realm, total_received_msgs: 100, total_received_bytes: 100)
      device_fixture(tenant: realm, total_received_msgs: 1, total_received_bytes: 1)

      target_1 =
        device_fixture(tenant: realm, total_received_msgs: 100, total_received_bytes: 1000)

      target_2 =
        device_fixture(tenant: realm, total_received_msgs: 300, total_received_bytes: 700)

      target_device_ids = [target_1.device_id, target_2.device_id]

      filter = %{
        "and" => [
          %{"totalReceivedMsgs" => %{"greater_than" => 50}},
          %{"totalReceivedBytes" => %{"greater_than" => 500}}
        ]
      }

      assert %{"edges" => [%{"node" => device_1}, %{"node" => device_2}]} =
               devices_query(tenant: realm, filter: filter)
               |> extract_result!()

      assert device_1["deviceId"] in target_device_ids
      assert device_2["deviceId"] in target_device_ids
    end
  end

  defp truncated_utc_now do
    DateTime.utc_now() |> DateTime.truncate(:millisecond)
  end

  defp devices_query(opts) do
    default_document =
      """
      query Devices(
        $filter: DeviceFilterInput,
        $sort: [DeviceSortInput],
        $after: String,
        $first: Int,
      ) {
        devices(filter: $filter, sort: $sort, after: $after, first: $first) {
          edges {
            node {
              id
              deviceId
              connected
              lastConnection
              lastDisconnection
              attributes
            }
            cursor
          }
          pageInfo {
            hasNextPage
          }
        }
      }
      """

    {tenant, opts} = Keyword.pop!(opts, :tenant)
    document = Keyword.get(opts, :document, default_document)

    variables =
      %{
        "after" => opts[:after],
        "first" => opts[:first],
        "filter" => opts[:filter],
        "sort" => opts[:sort] || []
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    Absinthe.run!(document, Astarte.AppEngine.APIWeb.Schema,
      variables: variables,
      context: %{tenant: tenant}
    )
  end

  defp extract_result!(result) do
    assert %{data: %{"devices" => device_connection}} = result
    assert device_connection != nil
    refute :errors in Map.keys(result)

    device_connection
  end
end
