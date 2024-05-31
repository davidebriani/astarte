defmodule Astarte.AppEngine.API.Devices.Device do
  use Ash.Resource,
    domain: Astarte.AppEngine.API.Devices,
    data_layer: AshScyllaDB.DataLayer,
    extensions: [AshGraphql.Resource]

  alias Astarte.AppEngine.API.Devices.Device.Changes
  alias Astarte.AppEngine.API.Devices.Device.Calculations

  graphql do
    type :device

    queries do
      get :device, :read
      list :devices, :read, relay?: true
    end
  end

  multitenancy do
    strategy :context
  end

  actions do
    defaults [:destroy]

    create :create do
      # This accepts all public attributes
      accept :*

      # We require device_id as argument, and convert it to a UUID below
      argument :device_id, :string do
        allow_nil? false
      end

      change Changes.SetDeviceId
    end

    read :read do
      primary? true

      pagination do
        keyset? true
        required? false
      end
    end
  end

  attributes do
    # In the struct the :id key will contain the device ID as a UUID
    # The UUID will be in the string representation since it's the path of least resistance
    # The :device_id key will contain the Device ID in the Astarte representation, see
    # the calculations sections
    uuid_primary_key :id do
      source :device_id
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

  calculations do
    calculate :device_id, :string, Calculations.DeviceId do
      public? true
    end
  end

  scylladb do
    repo Astarte.AppEngine.API.Repo
    table "devices"
    partition_key [:id]
  end
end
