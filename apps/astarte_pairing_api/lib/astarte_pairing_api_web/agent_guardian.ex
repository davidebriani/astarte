#
# This file is part of Astarte.
#
# Copyright 2017 Ispirata Srl
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

defmodule Astarte.Pairing.APIWeb.AgentGuardian do
  use Guardian, otp_app: :astarte_pairing_api

  alias Astarte.Pairing.API.Agent.Realm

  def subject_for_token(%Realm{realm_name: realm_name}, _claims) do
    {:ok, realm_name}
  end

  def resource_from_claims(claims) do
    {:ok, %Realm{realm_name: claims["routingTopic"]}}
  end
end
