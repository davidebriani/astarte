import Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :astarte_appengine_api, Astarte.AppEngine.APIWeb.Endpoint,
  http: [port: 4002],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: []

config :logger, :console,
  format: {PrettyLog.LogfmtFormatter, :format},
  metadata: [
    :method,
    :request_path,
    :status_code,
    :elapsed,
    :realm,
    :group_name,
    :device_alias,
    :device_id,
    :interface,
    :path,
    :module,
    :function,
    :request_id,
    :tag
  ]

config :astarte_appengine_api, Astarte.AppEngine.API.Repo,
  # List of database connection endpoints
  contact_points: ["127.0.0.1"],
  log: :info,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
