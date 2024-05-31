defmodule Astarte.AppEngine.API.Devices.Device.Calculations.DeviceId do
  use Ash.Resource.Calculation

  def calculate(records, _opts, _context) do
    device_ids =
      records
      |> Enum.map(fn record ->
        record.id
        |> Ecto.UUID.dump!()
        |> Astarte.Core.Device.encode_device_id()
      end)

    {:ok, device_ids}
  end
end
