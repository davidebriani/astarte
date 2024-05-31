defmodule Astarte.AppEngine.API.Devices.Device.Changes.SetDeviceId do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :device_id) do
      {:ok, encoded_device_id} when is_binary(encoded_device_id) ->
        case Astarte.Core.Device.decode_device_id(encoded_device_id) do
          {:ok, device_id} ->
            Ash.Changeset.force_change_attribute(changeset, :id, device_id)

          _ ->
            error =
              Ash.Error.Changes.InvalidArgument.exception(
                value: encoded_device_id,
                field: :device_id,
                message: "not a valid Astarte Device ID"
              )

            Ash.Changeset.add_error(changeset, error)
        end

      _ ->
        changeset
    end
  end
end
