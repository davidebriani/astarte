defmodule Astarte.AppEngine.API.Devices.Device.Calculations.GroupNames do
  use Ash.Resource.Calculation

  def load(_opts) do
    [:groups]
  end

  def calculate(records, _opts, _context) do
    {:ok, Enum.map(records, &Map.keys(&1.groups))}
  end
end
