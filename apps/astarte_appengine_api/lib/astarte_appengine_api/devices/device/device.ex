defmodule Astarte.AppEngine.API.Devices.Device do
  use Ash.Resource,
    domain: Astarte.AppEngine.API.Devices,
    data_layer: AshScyllaDB.DataLayer,
    extensions: [AshGraphql.Resource]

  alias Astarte.AppEngine.API.Devices.Device.DeviceId

  graphql do
    type :device

    queries do
      get :device, :read
      list :devices, :read, paginate_with: nil
    end
  end

  multitenancy do
    strategy :context
  end

  actions do
    defaults [:read, create: :*]
  end

  attributes do
    attribute :device_id, DeviceId do
      primary_key? true
      allow_nil? false
      public? true
    end

    # TODO: custom map types
    # attribute :aliases, :map do
    #   public? true
    # end

    # attribute :introspection, :map do
    #   public? true
    # end

    # attribute :old_introspection, :map do
    #   public? true
    # end

    attribute :first_registration, :utc_datetime_usec do
      public? true
    end

    attribute :inhibit_credentials_request, :boolean do
      public? true
    end

    attribute :first_credentials_request, :utc_datetime_usec do
      public? true
    end

    attribute :last_connection, :utc_datetime_usec do
      public? true
    end

    attribute :last_disconnection, :utc_datetime_usec do
      public? true
    end

    attribute :connected, :boolean do
      public? true
      default false
    end

    attribute :total_received_msgs, :integer do
      public? true
    end

    attribute :total_received_bytes, :integer do
      public? true
    end

    # TODO: custom map types
    # attribute :exchanged_bytes_by_interface, :map do
    #   public? true
    # end

    # attribute :exchanged_msgs_by_interface, :map do
    #   public? true
    # end

    # TODO: inet (https://github.com/vinniefranco/exandra/issues/59)
    # attribute :last_credentials_request_ip, :string do
    #   public? true
    # end

    # attribute :last_seen_ip, :string do
    #   public? true
    # end

    # TODO: handle custom Ecto types
    # attribute :attributes, :map do
    #   public? true
    # end

    # TODO: custom map types
    # attribute :groups, :map do
    #   public? true
    # end

    attribute :credentials_secret, :string
    attribute :cert_serial, :string
    attribute :cert_aki, :string
    attribute :pending_empty_cache, :boolean
  end

  scylladb do
    repo Astarte.AppEngine.API.Repo
    table "devices"
  end
end
