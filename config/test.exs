import Config

config :breakthrough, BreakthroughWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "mLVpqafE2cFmMkqvfYDnxDapJPNNR1BU+kxrC4dV9VIIOthqGrbZZeDADcfwF51k",
  server: false

config :breakthrough, Breakthrough.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
