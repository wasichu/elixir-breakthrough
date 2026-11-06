# Breakthrough

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- Strategy-game enthusiasts who may already know Breakthrough and want a quick browser match with a friend or the AI.
- People interested in seeing what Phoenix LiveView can do through a working game.

## Product Purpose

Make the abstract strategy board game Breakthrough playable in the browser. A successful visit lets a player start a match, share it with a friend or play against the AI, and understand the game well enough to play.

The live game also gives visitors a concrete example of Phoenix LiveView's capabilities.

## Operating Context

The existing app has a home lobby at `/` and individual matches at `/games/:id`.
Players create a multiplayer match and share its URL. The first visitor claims White, the second claims Black, and additional visitors watch as spectators. AI play is available from the home page.

Moves, player presence, lobby activity, resignations, and rematch requests update live. Players can move pieces by tapping, clicking, dragging with a mouse, or using the keyboard. Arrow keys explore the board even when waiting or spectating; Enter or Space selects a pawn or destination. Legal-move and last-move highlighting, move announcements, and a bounded recent-move trail support play. Illustrated rules are available from both the lobby and the match. Match presentation changes for invitations, active play, spectators, results, and expiration; expired matches retain the final position for review.

## Capabilities and Constraints

The following describe the current implementation, rather than new feature commitments:

- Phoenix 1.8 and LiveView provide the interface and real-time updates; Tailwind CSS 4 styles it.
- Browser sessions identify players without an account-registration flow. Each session may create one unfinished game at a time across multiplayer and AI modes. The lobby shows the current created game. Repeated create requests keep the player in the lobby with an explanation and explicit Return to game and, while waiting, Cancel waiting game actions. Finishing, cancelling a waiting game, or expiration frees the slot; a different browser session has its own limit.
- Game state lives in supervised in-memory processes. Active matches do not survive a server restart, and shared state across nodes is not implemented.
- White moves first. Pawns move one square straight or diagonally forward into empty squares and capture diagonally forward. Captures are optional and never chained. Reaching the opposing back rank or capturing every opposing pawn wins.
- The repository's `AGENTS.md` governs implementation conventions, including use of Phoenix components, bundled assets, and `mix precommit` verification.

## Evidence on Hand

- `README.md` describes the game, supported features, setup, deployment constraints, and GPL-3.0 licensing.
- `lib/breakthrough/game.ex` implements the rules; `lib/breakthrough/game_ai/` implements AI strategies.
- `lib/breakthrough_web/live/` contains the lobby, rules presentation, and playable match interface.
- `priv/static/images/logo.svg` and `priv/static/images/pawn.svg` are existing identity and game assets. Their presence is not a confirmed requirement to retain them unchanged.

## Product Principles

- Keep starting and sharing a browser match straightforward.
- Serve strategy-game enthusiasts while making the rules available to visitors who need them.
- Demonstrate LiveView through useful, observable game behavior.

## Open Decisions

- The user is flexible about product priorities and identity constraints. The immediate goal is to spruce up an app they have not worked on for a while; no additional preservation requirements were specified.
- No product-specific accessibility standard or additional audience needs have been established.
- Relative emphasis between playing the game and explaining its implementation remains undecided.
