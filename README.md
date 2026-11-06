<p align="center">
  <img src="priv/static/images/logo.svg" alt="Breakthrough logo" width="180" />
</p>

# Breakthrough

Breakthrough is a small real-time web implementation of [the abstract strategy
board game][wp]. Create a match, share the URL, and play in the browser. The first
visitor claims White, the second claims Black, and additional visitors can watch
as spectators.

The app is built with Phoenix LiveView and keeps the game state in supervised
processes, so moves, lobby status, rematches, resignations, and spectator views
update live without a separate frontend framework.

[Play Breakthrough][hp]

## Features

- Real-time player-vs-player games with shareable URLs
- One unfinished created game per browser session across multiplayer and AI modes
- Play-vs-AI mode
- Spectator support for active games
- Lobby with active game count and recent match links
- Drag or click pieces to move
- Legal move highlighting and last-move highlighting
- Rematch and resignation flows
- Rules modal with visual move/capture/win diagrams
- Phoenix LiveView UI with Tailwind CSS

## Rules Summary

White moves first. On each turn, move one pawn one square forward or diagonally
forward into an empty square. A pawn captures by moving one square diagonally
forward onto an opposing pawn. Captures are optional and are not chained.

Win by reaching the opponent's back rank or by capturing every opposing pawn.

## Game Lifetime

Waiting invitation links expire after 15 minutes. Once both seats are claimed
(including AI), the first move must happen within one minute. Started games
expire after 20 minutes without a move, and finished games remain viewable for
one minute. Disconnect cleanup also removes started multiplayer games after
both players leave for 10 seconds, or AI games five seconds after the human leaves.

The creator can cancel a waiting invitation from the lobby or match page.
Cancellation and expiry free the browser's creation slot and remove the lobby
entry. Expired links cannot recreate a game. Games created before a development
code reload need cancellation or a server restart to acquire new lifecycle timers.

## Tech Stack

- Elixir
- Phoenix 1.8
- Phoenix LiveView
- Tailwind CSS 4
- Bandit
- Req
- Swoosh

## Getting Started

Install [mise](https://mise.jdx.dev/getting-started.html), then install the pinned
Erlang, Elixir, Node.js, and Just versions and set up the application:

```sh
mise install
mise exec -- just setup
```

Start the Phoenix server:

```sh
mise exec -- just dev
```

Then open:

```text
http://localhost:4000
```

You can also run the app inside IEx:

```sh
mise exec -- just console
```

## Development Checks

Run the project checks before pushing changes (`just check` runs `mix precommit`):

```sh
mise exec -- just check
```

That runs compile with warnings as errors, unused dependency checks, formatting,
and the test suite.

Build assets directly when changing CSS or JavaScript:

```sh
mise exec -- just assets
```

Run `mise exec -- just` to list recipes. If mise is activated in your shell, the
`mise exec --` prefix is optional. Run a particular test with
`just test test/breakthrough/game_test.exs`.

GitHub Actions runs formatting checks, `mix precommit`, Playwright browser checks,
asset compilation, a production release build, and a Docker image build on pushes and pull requests. It installs the same tools
from `mise.toml`. Dependabot proposes weekly updates for Mix packages, GitHub
Actions, browser-test npm packages, and Docker images; updates require review and are not merged automatically.

Use `just outdated` to inspect dependency versions and `just update` to update
within `mix.exs` requirements and verify the result. Tool versions in `mise.toml`
and asset binary versions in `config/config.exs` are explicit pins; review their
upstream releases when updating them. Keep Elixir/OTP versions in `Dockerfile`
aligned with mise. `just release` builds locally and does not deploy.

## Browser Verification

```sh
mise exec -- just browser-setup
mise exec -- just browser-check
mise exec -- just browser-report
```

The committed Playwright suite starts its own Phoenix server in the test
configuration on port 4791, separate from development games. Set
`PLAYWRIGHT_PORT` to choose another port. Each test uses fresh browser sessions;
multiplayer scenarios give each player and spectator a separate context.

Tests cover desktop and mobile interactions, spatial keyboard navigation,
selection and dragging, sharing and the active-game limit, rules and resignation
focus behavior, a played-out breakthrough, rematches, layout boundaries, and
axe accessibility checks. Representative screenshots are attached to the report.
Failures retain screenshots and traces; CI uploads the reports for seven days.

Use `npm run test:e2e -- --grep "scenario name"` for a focused check. Review the
screenshots as well as assertions: automated accessibility checks and passing
interaction tests do not replace visual or screen-reader review. Agent-proposed
repairs must preserve the tested outcome rather than loosen it.

## Deployment Notes

The app is designed to deploy cleanly to Fly.io or another Phoenix-friendly
runtime. In production, set:

```sh
PHX_SERVER=true
PHX_HOST=your-domain.example
SECRET_KEY_BASE=...
```

Generate a secret with:

```sh
mix phx.gen.secret
```

The app currently stores game state in memory. That keeps the deployment simple,
but active games are tied to the running instance and will not survive a restart
or automatically span multiple nodes without additional clustering/state work.
Deploy exactly one application machine (`fly scale count 1` and
`fly deploy --ha=false`). Deployment restarts discard existing games.
`PHX_CHECK_ORIGINS` optionally supplies a comma-separated list of allowed HTTPS
origins; the default allows only `PHX_HOST`. Fly permits the custom domain and
its fly.dev hostname without disabling origin verification.

## Project Structure

- `lib/breakthrough/game.ex` contains pure game rules.
- `lib/breakthrough/game_ai/` contains AI move selection.
- `lib/breakthrough/games/` contains supervised game processes and lobby state.
- `lib/breakthrough_web/live/` contains the LiveView UI.
- `assets/js/hooks/` contains browser hooks for copy/share behavior and board dragging.
- `priv/static/images/` contains the pawn and logo assets.

## License

This project is licensed under the GNU General Public License v3.0.

[hp]: https://breakthrough.slowinput.org
[wp]: https://en.wikipedia.org/wiki/Breakthrough_(board_game)
