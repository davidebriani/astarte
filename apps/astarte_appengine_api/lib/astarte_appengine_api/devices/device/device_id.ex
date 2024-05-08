defmodule Astarte.AppEngine.API.Devices.Device.DeviceId do
  use Ash.Type
  use AshGraphql.Type

  alias Astarte.Core.Device

  @impl true
  def graphql_type(_), do: :string

  # Mainly taken from Ash.Type.UUID
  @impl true
  def storage_type(_), do: :uuid

  @impl true
  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(value, _) when is_binary(value) do
    if String.valid?(value) do
      case Device.decode_device_id(String.trim(value)) do
        {:ok, _} -> {:ok, value}
        _ -> :error
      end
    else
      case Ecto.Type.cast(Ecto.UUID, value) do
        {:ok, _} -> {:ok, Device.encode_device_id(value)}
        _ -> :error
      end
    end
  end

  def cast_input(value, _) do
    :error
  end

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(value, constraints) do
    case Ecto.Type.load(Ecto.UUID, value) do
      {:ok, _} ->
        {:ok, Device.encode_device_id(value)}

      :error ->
        :error
    end
  end

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(value, _) do
    case Device.decode_device_id(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :error
    end
  end
end
