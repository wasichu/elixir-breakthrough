You are refactoring an existing Phoenix + LiveView Breakthrough game into a real multiplayer game playable between two browsers.

Read these requirements carefully and follow them strictly.

GOAL

Turn the current local-only Breakthrough implementation into a server-authoritative multiplayer game where:

* two different browser sessions can join the same game by URL
* one player is white and one player is black
* additional visitors become spectators
* game state is owned on the server, not in a single LiveView
* moves are broadcast to all connected clients
* the same architecture can still support AI games

IMPORTANT CONSTRAINTS

* Keep Phoenix LiveView as the UI layer
* No database
* No accounts or authentication system
* No custom JavaScript required for V1 multiplayer
* No drag-and-drop
* Keep click-to-select and click-to-move
* Keep domain game logic in pure Elixir modules
* Do not overengineer reconnect logic, timers, or chat
* Keep styling changes minimal
* The multiplayer implementation should compile and run cleanly

CURRENT DOMAIN ASSUMPTIONS

The existing app already has or should preserve these domain concepts:

* board coordinates use 1-based indexing
* {1, 1} is top-left
* rows and cols are positive integers 1..8
* board is a sparse map:
  %{ {row, col} => :white | :black }
* white starts on rows 7 and 8
* black starts on rows 1 and 2

Move struct:

* from
* to
* player
* capture?

Game struct:

* board
* current_player
* winner
* move_history

ARCHITECTURE SHIFT

The current LiveView likely owns the game state in socket assigns.
Refactor so that:

* LiveView no longer owns the source of truth
* each game is owned by a dedicated GenServer
* clients subscribe to updates for a specific game via Phoenix PubSub
* LiveView reflects server state and sends move requests to the game process

ADD THESE MODULES

Create or update modules under:

lib/breakthrough/games/
game_server.ex
game_supervisor.ex
registry.ex
game_manager.ex

RESPONSIBILITIES

Breakthrough.Games.Registry

* use Elixir Registry for looking up game processes by id

Breakthrough.Games.GameSupervisor

* use DynamicSupervisor to supervise game processes

Breakthrough.Games.GameServer

* GenServer holding one game’s authoritative state

Suggested state shape:

%{
id: game_id,
game: %Breakthrough.Game{},
mode: :pvp | :vs_ai | :hotseat,
players: %{
white: player_token_or_nil,
black: player_token_or_nil
}
}

Breakthrough.Games.GameManager

* thin API wrapper for:

  * create_game/1 or create_game/0
  * ensure_game_started/1
  * get_state/1
  * join_game/2
  * make_move/4
  * new_game/1 or restart_game/1
  * set_mode/2 if useful

PLAYER IDENTITY

Since there are no accounts:

* assign each browser session a temporary player token
* store/reuse that token in the session if practical
* when visiting a game:

  * if white slot empty, assign white
  * else if black slot empty, assign black
  * else assign spectator

GAME SERVER API

Implement a clean public API around GameServer, such as:

* start_link(opts)
* get_state(game_id)
* join_game(game_id, player_token)
* make_move(game_id, player_token, from, to)
* restart_game(game_id)
* maybe set_mode(game_id, mode)

MOVE VALIDATION

All move validation must happen server-side in the GameServer flow.
The server must ensure:

* the game is not already over
* the requesting player is white or black, not spectator
* the requesting player matches game.current_player
* the requested move is legal according to the domain game logic

Do not trust the client.

PUBSUB

Use Phoenix PubSub with topics like:

* "game:<game_id>"

When game state changes:

* broadcast updated state to subscribers

LIVEVIEW REFACTOR

Refactor the current LiveView so it works against server-owned state.

Create or update a LiveView for routes like:

* /games/:id

Suggested assigns:

%{
game_id: "some-id",
game: %Breakthrough.Game{},
player_side: :white | :black | :spectator,
selected_square: nil,
legal_targets: MapSet.new(),
mode: :pvp,
board_theme: "classic"
}

MOUNT FLOW

On mount:

* read game_id from params
* ensure the game process exists
* get or create the browser’s player token from session if possible
* join the game through GameManager
* subscribe to PubSub topic for the game
* assign the latest game state and local player_side

LIVEVIEW EVENTS

Keep click-to-select and click-to-move.

Event handling rules:

* clicking your own piece on your turn selects it
* selecting a piece computes legal targets from current game state
* clicking the selected square clears selection
* clicking a legal target sends a move request to the server
* clicking another own piece switches selection
* spectators cannot move pieces
* users cannot move when it is not their turn

After a successful move:

* clear selected_square
* clear legal_targets

If a move is rejected:

* fail gracefully
* do not crash

PUBSUB HANDLING IN LIVEVIEW

Handle broadcast messages so that:

* all connected clients update to the latest game state
* selections/highlights are cleared if they are now stale
* the move list updates in both browsers

ROUTING

Add routes for:

* home page or landing page
* creating a new game
* viewing a specific game by id, e.g. /games/:id

A simple flow is enough:

* user clicks "New Game"
* server creates a game id
* redirect to /games/:id
* second user opens that URL to join

HOME PAGE / CONTROLS

Add minimal controls:

* New Game
* Copy/shareable game URL display if easy
* Show whether the user is White, Black, or Spectator
* Show whose turn it is
* Show winner if game over

AI SUPPORT

Preserve compatibility with AI mode.

Requirements:

* the architecture should still allow :vs_ai mode
* if mode is :vs_ai, the GameServer should trigger AI moves server-side
* AI should only run after a valid human move
* if AI move support already exists, refactor it so the server owns it
* if needed, leave a TODO or simple server-side hook for delayed AI execution

STYLING

Keep styling minimal.
Do not spend time polishing visuals beyond what is needed for the refactor.

BOARD THEME PREP

Do a small amount of prep for future board color customization:

* support a board_theme assign like "classic"
* wrap board UI with a theme class such as theme-classic
* do not implement a full theme system yet unless trivial

IMPLEMENTATION STYLE

* Prefer small, clear modules
* Keep GenServer API explicit
* Add @doc comments for public functions
* Add TODO comments where future improvements are obvious
* Avoid giant abstractions
* Avoid unnecessary macros
* Avoid adding a database or persistence layer

DELIVERABLE

Produce a working multiplayer refactor that:

* supports two-browser play by shared URL
* is server-authoritative
* uses GenServer + DynamicSupervisor + Registry + PubSub
* preserves existing domain game logic boundaries
* leaves the app in a clean state for future AI polish and board color customization

