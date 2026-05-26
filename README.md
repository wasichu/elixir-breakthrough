# Breakthrough

<p align="center">
  <img src="priv/static/images/logo.svg" alt="Breakthrough logo" width="180" />
</p>

Breakthrough is a small real-time web implementation of the abstract strategy
board game. Create a match, share the URL, and play in the browser. The first
visitor claims White, the second claims Black, and additional visitors can watch
as spectators.

The app is built with Phoenix LiveView and keeps the game state in supervised
processes, so moves, lobby status, rematches, resignations, and spectator views
update live without a separate frontend framework.

## Features

- Real-time player-vs-player games with shareable URLs
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

## Tech Stack

- Elixir
- Phoenix 1.8
- Phoenix LiveView
- Tailwind CSS 4
- Bandit
- Req
- Swoosh

## Getting Started

Install dependencies and build assets:

```sh
mix setup
```

Start the Phoenix server:

```sh
mix phx.server
```

Then open:

```text
http://localhost:4000
```

You can also run the app inside IEx:

```sh
iex -S mix phx.server
```

## Development Checks

Run the project precommit alias before pushing changes:

```sh
mix precommit
```

That runs compile with warnings as errors, unused dependency checks, formatting,
and the test suite.

Build assets directly when changing CSS or JavaScript:

```sh
mix assets.build
```

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

## Project Structure

- `lib/breakthrough/game.ex` contains pure game rules.
- `lib/breakthrough/game_ai/` contains AI move selection.
- `lib/breakthrough/games/` contains supervised game processes and lobby state.
- `lib/breakthrough_web/live/` contains the LiveView UI.
- `assets/js/hooks/` contains browser hooks for copy/share behavior and board dragging.
- `priv/static/images/` contains the pawn and logo assets.

## License

This project is licensed under the GNU General Public License v3.0.
