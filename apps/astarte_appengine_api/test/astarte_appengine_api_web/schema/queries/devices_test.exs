defmodule Astarte.AppEngine.APIWeb.Schema.Queries.DevicesTest do
  use Astarte.AppEngine.APIWeb.GraphqlCase, async: true

  describe "devices query" do
    test "returns empty devices", %{realm: realm} do
      assert [] == devices_query(tenant: realm) |> extract_result!()
    end
  end

  defp devices_query(opts) do
    default_document =
      """
      query Devices($filter: DeviceFilterInput, $sort: [DeviceSortInput]) {
        devices(filter: $filter, sort: $sort) {
          id
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
