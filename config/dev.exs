use Mix.Config

config :ae_mdw, AeMdwWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  watchers: [],
  check_origin: false

config :ae_mdw, AeMdwWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/gettext/.*(po)$",
      ~r"lib/test_web/(live|views)/.*(ex)$",
      ~r"lib/test_web/templates/.*(eex)$"
    ]
  ]

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Note that this task requires Erlang/OTP 20 or later.
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

if File.exists?(Path.join([__DIR__, "dev.tools.exs"])) do
  import_config "dev.tools.exs"
end
