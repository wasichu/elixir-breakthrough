set positional-arguments

# List the supported development commands.
default:
    @just --list

# Install Hex/Rebar, fetch dependencies, and build assets after mise install.
setup:
    mix local.hex --force
    mix local.rebar --force
    mix setup
    npm ci

# Start Phoenix with live code and asset reloading.
dev:
    mix phx.server

# Start Phoenix in an interactive Elixir shell.
console:
    iex -S mix phx.server

# Run tests, optionally passing a file, line number, or Mix test options.
test *args:
    mix test "$@"

# Format Elixir and HEEx source.
format:
    mix format

# Run the required project checks (includes formatting).
check:
    mix precommit

# Verify formatting before running checks so CI never silently repairs it.
ci:
    mix format --check-formatted
    mix deps.unlock --check-unused
    mix precommit
    mix assets.build
    npm run test:e2e

# Build CSS and JavaScript.
assets:
    mix assets.build

# Build production assets and the release; never deploys it.
release:
    MIX_ENV=prod mix assets.deploy
    MIX_ENV=prod mix release --overwrite

# Report outdated direct and transitive Hex packages.
outdated:
    mix hex.outdated --all

# Update dependencies within mix.exs constraints, then verify.
update:
    mix deps.update --all
    just check
    just assets

# Install the Chromium version pinned by Playwright.
browser-setup:
    npm ci
    npx playwright install chromium

# Run isolated desktop/mobile browser tests, accessibility checks, and screenshots.
browser-check:
    npm run test:e2e

# Open the latest local Playwright report.
browser-report:
    npm run test:e2e:report
