#
# This file is part of Astarte.
#
# Copyright 2017-2020 Ispirata Srl
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

defmodule Astarte.AppEngine.API.Mixfile do
  use Mix.Project

  def project do
    [
      app: :astarte_appengine_api,
      version: "1.0.0-beta.1",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer_cache_directory: dialyzer_cache_directory(Mix.env()),
      deps: deps() ++ astarte_required_modules(System.get_env("ASTARTE_IN_UMBRELLA"))
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Astarte.AppEngine.API.Application, []},
      extra_applications: [:lager, :logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer_cache_directory(:ci) do
    "dialyzer_cache"
  end

  defp dialyzer_cache_directory(_) do
    nil
  end

  defp astarte_required_modules("true") do
    [
      {:astarte_core, in_umbrella: true},
      {:astarte_data_access, in_umbrella: true},
      {:astarte_rpc, in_umbrella: true}
    ]
  end

  defp astarte_required_modules(_) do
    [
      {:astarte_core, "== 1.0.0-beta.1"},
      {:astarte_data_access, "== 1.0.0-beta.1"},
      {:astarte_rpc, "== 1.0.0-beta.1"}
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:phoenix_ecto, "~> 4.0"},
      {:gettext, "~> 0.11"},
      {:plug_cowboy, "~> 2.1"},
      {:jason, "~> 1.2"},
      {:cors_plug, "~> 2.0"},
      {:ex_lttb, "~> 0.3"},
      {:cyanide, "~> 1.0"},
      {:guardian, "~> 2.1"},
      {:phoenix_swagger, "~> 0.8"},
      {:xandra, "~> 0.13"},
      {:excoveralls, "~> 0.12", only: :test},
      {:mox, "~> 0.5", only: :test},
      {:pretty_log, "~> 0.1"},
      {:plug_logger_with_meta, "~> 0.1"},
      {:telemetry, "~> 0.4"},
      {:telemetry_metrics, "~> 0.4"},
      {:telemetry_poller, "~> 0.4"},
      {:telemetry_metrics_prometheus_core, "~> 0.4"},
      {:skogsra, "~> 2.2"},
      {:castore, "~> 0.1.0"},
      {:observer_cli, "~> 1.5"},
      {:dialyzex, github: "Comcast/dialyzex", only: [:dev, :ci]}
    ]
  end
end
