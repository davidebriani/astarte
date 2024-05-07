defmodule Astarte.AppEngine.API.Repo do
  use Ecto.Repo, otp_app: :astarte_appengine_api, adapter: Exandra
end
