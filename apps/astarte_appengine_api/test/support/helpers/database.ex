#
# This file is part of Astarte.
#
# Copyright 2025 SECO Mind Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

defmodule Astarte.Test.Helpers.Database do
  alias Astarte.DataAccess.Repo
  alias Astarte.DataAccess.Realms.Realm

  alias Astarte.Core.Mapping.EndpointsAutomaton

  alias Astarte.DataAccess.Realms.Interface
  alias Astarte.DataAccess.Devices.Device
  alias Astarte.DataAccess.Realms.Endpoint
  alias Astarte.DataAccess.Realms.Name
  alias Astarte.Core.CQLUtils
  alias Astarte.Core.InterfaceDescriptor
  alias Astarte.Core.Interface.Aggregation
  alias Astarte.Core.Interface.Ownership
  alias Astarte.Core.Interface.Type, as: InterfaceType
  alias Astarte.Core.Mapping
  alias Astarte.Core.Mapping.DatabaseRetentionPolicy
  alias Astarte.Core.Mapping.Reliability
  alias Astarte.Core.Mapping.Retention
  alias Astarte.Core.Mapping.ValueType
  alias Astarte.Core.StorageType
  alias Astarte.DataAccess.Consistency
  alias Astarte.AppEngine.API.JWTTestHelper

  @create_keyspace """
  CREATE KEYSPACE IF NOT EXISTS :keyspace
    WITH
      replication = {'class': 'SimpleStrategy', 'replication_factor': '1'} AND
      durable_writes = true;
  """

  @drop_keyspace """
  DROP KEYSPACE IF EXISTS :keyspace
  """

  @create_realms_table """
  CREATE TABLE IF NOT EXISTS :keyspace.realms (
    realm_name varchar,

    PRIMARY KEY (realm_name)
  );
  """

  @create_kv_store """
  CREATE TABLE IF NOT EXISTS :keyspace.kv_store (
    group varchar,
    key varchar,
    value blob,

    PRIMARY KEY ((group), key)
  )
  """

  @create_names_table """
  CREATE TABLE IF NOT EXISTS :keyspace.names (
    object_name varchar,
    object_type int,
    object_uuid uuid,

    PRIMARY KEY ((object_name), object_type)
  )
  """

  @create_devices_table """
  CREATE TABLE IF NOT EXISTS :keyspace.devices (
    device_id uuid,
    aliases map<ascii, varchar>,
    introspection map<ascii, int>,
    introspection_minor map<ascii, int>,
    old_introspection map<frozen<tuple<ascii, int>>, int>,
    protocol_revision int,
    first_registration timestamp,
    credentials_secret ascii,
    inhibit_credentials_request boolean,
    cert_serial ascii,
    cert_aki ascii,
    first_credentials_request timestamp,
    last_connection timestamp,
    last_disconnection timestamp,
    connected boolean,
    pending_empty_cache boolean,
    total_received_msgs bigint,
    total_received_bytes bigint,
    exchanged_bytes_by_interface map<frozen<tuple<ascii, int>>, bigint>,
    exchanged_msgs_by_interface map<frozen<tuple<ascii, int>>, bigint>,
    last_credentials_request_ip inet,
    last_seen_ip inet,
    attributes map<varchar, varchar>,

    groups map<text, timeuuid>,

    PRIMARY KEY (device_id)
  )
  """

  @create_deletion_in_progress_table """
  CREATE TABLE IF NOT EXISTS :keyspace.deletion_in_progress (
    device_id uuid,
    vmq_ack boolean,
    dup_start_ack boolean,
    dup_end_ack boolean,

    PRIMARY KEY (device_id)
  );
  """

  @create_interfaces_table """
  CREATE TABLE IF NOT EXISTS :keyspace.interfaces (
    name ascii,
    major_version int,
    minor_version int,
    interface_id uuid,
    storage_type int,
    storage ascii,
    type int,
    ownership int,
    aggregation int,
    automaton_transitions blob,
    automaton_accepting_states blob,
    description text,
    doc text,

    PRIMARY KEY (name, major_version)
  )
  """

  @create_endpoints_table """
  CREATE TABLE IF NOT EXISTS :keyspace.endpoints (
    interface_id uuid,
    endpoint_id uuid,
    interface_name ascii,
    interface_major_version int,
    interface_minor_version int,
    interface_type int,
    endpoint ascii,
    value_type int,
    reliability int,
    retention int,
    expiry int,
    database_retention_ttl int,
    database_retention_policy int,
    allow_unset boolean,
    explicit_timestamp boolean,
    description text,
    doc text,

    PRIMARY KEY ((interface_id), endpoint_id)
  )
  """

  @create_simple_triggers_table """
  CREATE TABLE IF NOT EXISTS :keyspace.simple_triggers (
    object_id uuid,
    object_type int,
    parent_trigger_id uuid,
    simple_trigger_id uuid,
    trigger_data blob,
    trigger_target blob,

    PRIMARY KEY ((object_id, object_type), parent_trigger_id, simple_trigger_id)
  );
  """

  @create_individual_properties_table """
  CREATE TABLE IF NOT EXISTS :keyspace.individual_properties (
    device_id uuid,
    interface_id uuid,
    endpoint_id uuid,
    path text,
    reception_timestamp timestamp,
    reception_timestamp_submillis smallint,
    double_value double,
    integer_value int,
    boolean_value boolean,
    longinteger_value bigint,
    string_value text,
    binaryblob_value blob,
    datetime_value timestamp,
    doublearray_value list<double>,
    integerarray_value list<int>,
    booleanarray_value list<boolean>,
    longintegerarray_value list<bigint>,
    stringarray_value list<text>,
    binaryblobarray_value list<blob>,
    datetimearray_value list<timestamp>,

    PRIMARY KEY((device_id, interface_id), endpoint_id, path)
  );
  """

  @create_individual_datastreams_table """
  CREATE TABLE IF NOT EXISTS :keyspace.individual_datastreams (
      device_id uuid,
      interface_id uuid,
      endpoint_id uuid,
      path text,
      value_timestamp timestamp,
      reception_timestamp timestamp,
      reception_timestamp_submillis smallint,
      binaryblob_value blob,
      binaryblobarray_value list<blob>,
      boolean_value boolean,
      booleanarray_value list<boolean>,
      datetime_value timestamp,
      datetimearray_value list<timestamp>,
      double_value double,
      doublearray_value list<double>,
      integer_value int,
      integerarray_value list<int>,
      longinteger_value bigint,
      longintegerarray_value list<bigint>,
      string_value text,
      stringarray_value list<text>,
      PRIMARY KEY ((device_id, interface_id, endpoint_id, path), value_timestamp, reception_timestamp, reception_timestamp_submillis)
  )
  """

  @create_groups_table """
  CREATE TABLE IF NOT EXISTS :keyspace.grouped_devices (
    group_name varchar,
    insertion_uuid timeuuid,
    device_id uuid,
    PRIMARY KEY ((group_name), insertion_uuid, device_id)
  )
  """

  @insert_public_key """
    INSERT INTO :keyspace.kv_store (group, key, value)
    VALUES ('auth', 'jwt_public_key_pem', varcharAsBlob(:pem));
  """

  def setup_realm!(realm_name) do
    keyspace = Realm.keyspace_name(realm_name)
    execute!(keyspace, @create_keyspace)
    execute!(keyspace, @create_devices_table)
    execute!(keyspace, @create_deletion_in_progress_table)
    execute!(keyspace, @create_groups_table)
    execute!(keyspace, @create_names_table)
    execute!(keyspace, @create_kv_store)
    execute!(keyspace, @create_endpoints_table)
    execute!(keyspace, @create_simple_triggers_table)
    execute!(keyspace, @create_individual_properties_table)
    execute!(keyspace, @create_individual_datastreams_table)
    execute!(keyspace, @create_interfaces_table)
    execute!(keyspace, @insert_public_key, %{"pem" => JWTTestHelper.public_key_pem()})

    astarte_keyspace = Realm.astarte_keyspace_name()
    execute!(astarte_keyspace, @create_keyspace)
    execute!(astarte_keyspace, @create_kv_store)
    execute!(astarte_keyspace, @create_realms_table)

    %Realm{realm_name: realm_name}
    |> Repo.insert!(prefix: astarte_keyspace)

    :ok
  end

  def teardown_realm!(realm_name) do
    keyspace = Realm.keyspace_name(realm_name)
    astarte_keyspace = Realm.astarte_keyspace_name()

    execute!(keyspace, @drop_keyspace)
    execute!(astarte_keyspace, @drop_keyspace)

    :ok
  end

  def insert_device!(realm_name, device \\ %{}) do
    keyspace = Realm.keyspace_name(realm_name)

    device =
      Device
      |> struct(device)
      |> Ecto.Changeset.change()
      |> Repo.insert!(prefix: keyspace)

    for {_key, device_alias} <- device.aliases || %{} do
      insert_device_alias!(realm_name, device.device_id, device_alias)
    end

    device
  end

  def insert_device_alias!(realm_name, device_id, device_alias) do
    keyspace = Realm.keyspace_name(realm_name)

    %Name{}
    |> Ecto.Changeset.change(%{
      object_name: device_alias,
      object_type: 1,
      object_uuid: device_id
    })
    |> Repo.insert!(prefix: keyspace)
  end

  def insert_interface!(realm_name, interface) do
    keyspace = Realm.keyspace_name(realm_name)
    {:ok, automaton} = EndpointsAutomaton.build(interface.mappings)

    IO.inspect(automaton)

    table_type =
      if interface.aggregation == :individual,
        do: :multi,
        else: :one

    {storage_type, table_name} =
      create_interface_table(
        keyspace,
        interface.aggregation,
        table_type,
        InterfaceDescriptor.from_interface(interface),
        interface.mappings
      )

    {transitions, accepting_states_no_ids} = automaton

    transitions_bin = :erlang.term_to_binary(transitions)

    accepting_states_bin =
      accepting_states_no_ids
      |> replace_automaton_acceptings_with_ids(
        interface.name,
        interface.major_version
      )
      |> :erlang.term_to_binary()

    # Here order matters, must be the same as the `?` in `insert_interface_statement`
    params =
      [
        interface.name,
        interface.major_version,
        interface.minor_version,
        interface.interface_id,
        StorageType.to_int(storage_type),
        table_name,
        InterfaceType.to_int(interface.type),
        Ownership.to_int(interface.ownership),
        Aggregation.to_int(interface.aggregation),
        transitions_bin,
        accepting_states_bin,
        interface.description,
        interface.doc
      ]

    interface_table = Interface.__schema__(:source)

    insert_interface_statement = """
      INSERT INTO #{keyspace}.#{interface_table}
        (name, major_version, minor_version, interface_id, storage_type, storage, type, ownership, aggregation, automaton_transitions, automaton_accepting_states, description, doc)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    interface_query = {insert_interface_statement, params}

    endpoints_queries =
      for mapping <- interface.mappings do
        insert_mapping_query(
          keyspace,
          interface.interface_id,
          interface.name,
          interface.major_version,
          interface.minor_version,
          interface.type,
          mapping
        )
      end

    consistency = Consistency.domain_model(:write)

    Exandra.execute_batch(
      Repo,
      %Exandra.Batch{
        queries: [interface_query | endpoints_queries]
      },
      consistency: consistency
    )
  end

  defp create_interface_table(
         _keyspace,
         :individual,
         :multi,
         %InterfaceDescriptor{type: :properties},
         _mappings
       ) do
    {:multi_interface_individual_properties_dbtable, "individual_properties"}
  end

  defp create_interface_table(
         _keyspace,
         :individual,
         :multi,
         %InterfaceDescriptor{type: :datastream},
         _mappings
       ) do
    {:multi_interface_individual_datastream_dbtable, "individual_datastreams"}
  end

  defp create_interface_table(keyspace, :object, :one, interface_descriptor, mappings) do
    table_name =
      CQLUtils.interface_name_to_table_name(
        interface_descriptor.name,
        interface_descriptor.major_version
      )

    columns = create_one_object_columns_for_mappings(mappings)

    [%Mapping{explicit_timestamp: explicit_timestamp} | _tail] = mappings

    {value_timestamp, key_timestamp} =
      if explicit_timestamp,
        do: {"value_timestamp timestamp,", "value_timestamp,"},
        else: {"", ""}

    create_interface_table_with_object_aggregation = """
     CREATE TABLE #{keyspace}.#{table_name} (
       device_id uuid,
       path varchar,

       #{value_timestamp},
       reception_timestamp timestamp,
       reception_timestamp_submillis smallint,
       #{columns},

       PRIMARY KEY((device_id, path), #{key_timestamp} reception_timestamp, reception_timestamp_submillis)
     )
    """

    _ = Repo.query(create_interface_table_with_object_aggregation)

    {:one_object_datastream_dbtable, table_name}
  end

  defp create_one_object_columns_for_mappings(mappings) do
    for %Mapping{endpoint: endpoint, value_type: value_type} <- mappings do
      column_name = CQLUtils.endpoint_to_db_column_name(endpoint)
      cql_type = CQLUtils.mapping_value_type_to_db_type(value_type)
      "#{column_name} #{cql_type}"
    end
    |> Enum.join(~s(,\n))
  end

  # TODO: this was needed when Cassandra used to generate endpoint IDs
  # it might be a good idea to drop this and generate those IDs in A.C.Mapping.EndpointsAutomaton
  defp replace_automaton_acceptings_with_ids(accepting_states, interface_name, major) do
    Enum.reduce(accepting_states, %{}, fn state, new_states ->
      {state_index, endpoint} = state

      Map.put(new_states, state_index, CQLUtils.endpoint_id(interface_name, major, endpoint))
    end)
  end

  defp insert_mapping_query(
         keyspace,
         interface_id,
         interface_name,
         major,
         minor,
         interface_type,
         mapping
       ) do
    table_name = Endpoint.__schema__(:source)

    insert_mapping_statement = """
    INSERT INTO #{keyspace}.#{table_name}
    (
     interface_id, endpoint_id, interface_name, interface_major_version, interface_minor_version,
     interface_type, endpoint, value_type, reliability, retention, database_retention_policy,
     database_retention_ttl, expiry, allow_unset, explicit_timestamp, description, doc
    )
    VALUES (
     ?, ?, ?, ?, ?,
     ?, ?, ?, ?, ?, ?,
     ?, ?, ?, ?, ?, ?
    )
    """

    params = [
      interface_id,
      mapping.endpoint_id,
      interface_name,
      major,
      minor,
      InterfaceType.to_int(interface_type),
      mapping.endpoint,
      ValueType.to_int(mapping.value_type),
      Reliability.to_int(mapping.reliability),
      Retention.to_int(mapping.retention),
      DatabaseRetentionPolicy.to_int(mapping.database_retention_policy),
      mapping.database_retention_ttl,
      mapping.expiry,
      mapping.allow_unset,
      mapping.explicit_timestamp,
      mapping.description,
      mapping.doc
    ]

    {insert_mapping_statement, params}
  end

  defp execute!(keyspace, query, params \\ [], opts \\ []) do
    String.replace(query, ":keyspace", keyspace)
    |> Repo.query!(params, opts)
  end
end
