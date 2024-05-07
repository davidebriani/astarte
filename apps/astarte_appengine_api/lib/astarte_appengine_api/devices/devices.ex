defmodule Astarte.AppEngine.API.Devices do
  use Ash.Domain,
    extensions: [AshGraphql.Domain]

  graphql do
    authorize? false
  end

  resources do
    resource Astarte.AppEngine.API.Devices.Device
  end
end
