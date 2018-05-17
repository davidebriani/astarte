#
# This file is part of Astarte.
#
# Astarte is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Astarte is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Astarte.  If not, see <http://www.gnu.org/licenses/>.
#
# Copyright (C) 2017-2018 Ispirata Srl
#

defmodule Astarte.Pairing.Engine do
  @moduledoc """
  This module performs the pairing operations requested via RPC.
  """

  alias Astarte.Core.Device
  alias Astarte.Pairing.CertVerifier
  alias Astarte.Pairing.CFSSLCredentials
  alias Astarte.Pairing.Config
  alias Astarte.Pairing.CredentialsSecret
  alias Astarte.Pairing.Queries
  alias CQEx.Client

  require Logger

  @version Mix.Project.config()[:version]

  def get_credentials(
        :astarte_mqtt_v1,
        %{csr: csr},
        realm,
        hardware_id,
        credentials_secret,
        device_ip
      ) do
    with {:ok, device_id} <- Device.decode_device_id(hardware_id, allow_extended_id: true),
         {:ok, ip_tuple} <- parse_ip(device_ip),
         {:ok, client} <- Config.cassandra_node() |> Client.new(keyspace: realm),
         {:ok, device_row} <- Queries.select_device_for_credentials_request(client, device_id),
         {:authorized?, true} <-
           {:authorized?,
            CredentialsSecret.verify(credentials_secret, device_row[:credentials_secret])},
         {:credentials_inhibited?, false} <-
           {:credentials_inhibited?, device_row[:inhibit_credentials_request]},
         _ <- CFSSLCredentials.revoke(device_row[:cert_serial], device_row[:cert_aki]),
         {:ok, %{cert: cert, aki: _aki, serial: _serial} = cert_data} <-
           CFSSLCredentials.get_certificate(csr, realm, device_row[:extended_id]),
         :ok <-
           Queries.update_device_after_credentials_request(
             client,
             device_id,
             cert_data,
             ip_tuple,
             device_row[:first_credentials_request]
           ) do
      {:ok, %{client_crt: cert}}
    else
      {:authorized?, false} ->
        {:error, :unauthorized}

      {:credentials_inhibited?, true} ->
        {:error, :credentials_request_inhibited}

      {:error, :shutdown} ->
        {:error, :realm_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_credentials(
        protocol,
        credentials_params,
        _realm,
        _hw_id,
        _credentials_secret,
        _device_ip
      ) do
    Logger.warn(
      "get_credentials: unknown protocol #{inspect(protocol)} with params #{
        inspect(credentials_params)
      }"
    )

    {:error, :unknown_protocol}
  end

  def get_info do
    %{version: @version, url: Config.broker_url!()}
  end

  def register_device(realm, hardware_id) do
    with {:ok, device_id} <- Device.decode_device_id(hardware_id, allow_extended_id: true),
         cassandra_node <- Config.cassandra_node(),
         {:ok, client} <- Client.new(cassandra_node, keyspace: realm),
         credentials_secret <- CredentialsSecret.generate(),
         secret_hash <- CredentialsSecret.hash(credentials_secret),
         :ok <- Queries.register_device(client, device_id, hardware_id, secret_hash) do
      {:ok, credentials_secret}
    else
      {:error, :shutdown} ->
        {:error, :realm_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify_certificate(pem_cert) do
    CertVerifier.verify(pem_cert, Config.ca_cert())
  end

  defp parse_ip(ip_string) do
    case to_charlist(ip_string) |> :inet.parse_address() do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, _} -> {:error, :invalid_ip}
    end
  end
end
