defmodule Astarte.AppEngine.APIWeb.Schema do
  use Absinthe.Schema

  use AshGraphql,
    relay_ids?: true,
    domains: [Astarte.AppEngine.API.Devices]

  query do
  end

  mutation do
  end
end
