import Config

config :breakthrough, BreakthroughWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "Mv1N2JH4lt+UymUVOPHR430fH1cm6uplk8zT/Y+yKh1jNKv2VGdyou4/2ONyGhUK",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:breakthrough, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:breakthrough, ~w(--watch)]}
  ]

config :breakthrough, BreakthroughWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/breakthrough_web/(?:controllers|live|components|router)/?.*\.(ex|heex)$"
    ]
  ]

config :breakthrough, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
