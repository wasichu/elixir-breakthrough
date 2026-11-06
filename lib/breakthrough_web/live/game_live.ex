defmodule BreakthroughWeb.GameLive do
  use BreakthroughWeb, :live_view

  alias Breakthrough.Game
  import BreakthroughWeb.RulesComponents, only: [rules_modal: 1]

  import BreakthroughWeb.MatchComponents,
    only: [share_controls: 1, player_strip: 1, resign_dialog: 1]

  alias Breakthrough.Games.GameManager
  alias Breakthrough.Games.GameServer

  @impl true
  def mount(%{"id" => game_id}, %{"player_token" => player_token}, socket) do
    socket =
      socket
      |> assign(:current_scope, nil)
      |> assign(:show_rules_modal, false)
      |> assign(:show_resign_dialog, false)
      |> assign(:show_guidance?, true)
      |> assign(:expiry_notice, nil)
      |> assign(:game_id, game_id)
      |> assign(:player_token, player_token)

    with {:ok, player_side, state} <- GameManager.join_game(game_id, player_token),
         {:ok, state} <- connect_to_game(socket, state) do
      {:ok,
       socket
       |> assign(:player_side, player_side)
       |> assign(:selected_square, nil)
       |> assign(:legal_targets, MapSet.new())
       |> assign(:game_expired, false)
       |> assign_multiplayer_state(state)}
    else
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That game is no longer available.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("select-square", %{"row" => row, "col" => col}, socket) do
    with {:ok, row} <- board_index(row), {:ok, col} <- board_index(col) do
      coord = {row, col}

      socket =
        cond do
          socket.assigns.selected_square == coord ->
            clear_local_selection(socket)

          selectable_piece?(socket.assigns, coord) ->
            select_square(socket, coord)

          move_allowed?(socket.assigns, coord) ->
            make_move(socket, coord)

          should_clear_selection?(socket.assigns) ->
            clear_local_selection(socket)

          true ->
            socket
        end

      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Choose a square on the board.")}
    end
  end

  def handle_event("select-square", _params, socket) do
    {:noreply, put_flash(socket, :error, "Choose a square on the board.")}
  end

  def handle_event("dismiss-guidance", _params, socket) do
    {:noreply, assign(socket, :show_guidance?, false)}
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, clear_local_selection(socket)}
  end

  def handle_event("request-resign", _params, socket) do
    {:noreply,
     assign(
       socket,
       :show_resign_dialog,
       show_resign_button?(
         socket.assigns.game,
         socket.assigns.player_side,
         socket.assigns.players
       )
     )}
  end

  def handle_event("close-resign", _params, socket) do
    {:noreply, assign(socket, :show_resign_dialog, false)}
  end

  def handle_event("open-rules", _params, socket) do
    {:noreply, assign(socket, :show_rules_modal, true)}
  end

  def handle_event("close-rules", _params, socket) do
    {:noreply, assign(socket, :show_rules_modal, false)}
  end

  def handle_event("cancel-game", _params, socket) do
    case GameManager.cancel_game(socket.assigns.game_id, socket.assigns.player_token) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Waiting game cancelled. You can start a new match.")
         |> push_navigate(to: ~p"/")}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This game can no longer be cancelled. Resign to end your game."
         )}
    end
  end

  def handle_event("resign-game", _params, socket) do
    case GameManager.resign(socket.assigns.game_id, socket.assigns.player_token) do
      {:ok, state} ->
        {:noreply,
         socket
         |> assign(:show_resign_dialog, false)
         |> clear_local_selection()
         |> assign_multiplayer_state(state)}

      {:error, :spectator} ->
        {:noreply, put_flash(socket, :error, "Spectators cannot resign a game.")}

      {:error, :game_over} ->
        {:noreply, put_flash(socket, :error, "This game is already finished.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That game is no longer available.")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("rematch-game", _params, socket) do
    case GameManager.create_rematch(socket.assigns.game_id, socket.assigns.player_token) do
      {:ok, _game_id} ->
        {:noreply, socket}

      {:pending, state} ->
        {:noreply, assign_multiplayer_state(socket, state)}

      {:error, {:active_game, game_id}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "You already have an active game. Finish it before starting a rematch."
         )
         |> push_navigate(to: ~p"/games/#{game_id}")}

      {:error, :spectator} ->
        {:noreply, put_flash(socket, :error, "Spectators cannot start a rematch.")}

      {:error, :not_finished} ->
        {:noreply, put_flash(socket, :error, "Rematch is only available after the game ends.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "That game is no longer available.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:game_updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:game_expired, false)
     |> assign_multiplayer_state(state)
     |> sync_local_selection()}
  end

  def handle_info({:game_expired, :cancelled}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Waiting game cancelled. You can start a new match.")
     |> push_navigate(to: ~p"/")}
  end

  @impl true
  def handle_info({:game_expired, reason}, socket) do
    {:noreply,
     socket
     |> assign(
       game_expired: true,
       phase: "Expired",
       turn: "–",
       expiry_notice: game_expired_message(reason),
       can_interact?: false,
       show_resign_dialog: false,
       table_title: "This game has expired",
       table_detail:
         "The final position is kept here so you can review it. Return to the lobby to start a new match."
     )
     |> clear_local_selection()}
  end

  @impl true
  def handle_info({:rematch_created, game_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} compact>
      <div id="game-shell" class="match-table">
        <header class="match-heading">
          <.link navigate={~p"/"} id="back-to-lobby" class="match-back-link">
            <.icon name="hero-arrow-left" class="size-4" /> Lobby
          </.link>
          <h1 class="display-copy text-xl text-stone-100 sm:text-2xl">
            {if @mode == :vs_ai, do: "Play vs AI", else: "Multiplayer"}
          </h1>
          <p class="match-role">
            <span id="player-side-value" data-side={@player_side} class="font-semibold text-stone-100">{if @player_side ==
                                                                                                             :spectator,
                                                                                                           do:
                                                                                                             "Spectator",
                                                                                                           else:
                                                                                                             "You · #{@player_side_label}"}</span>
          </p>
        </header>

        <section id="game-status-panel" class="match-state" aria-labelledby="phase-value">
          <div id="turn-summary" aria-live="polite" aria-atomic="true">
            <h2
              id="phase-value"
              data-phase={@phase}
              class="display-copy text-3xl text-stone-100 sm:text-4xl"
            >
              {@table_title}
            </h2>
            <p id="board-prompt" class="mt-2 max-w-prose text-sm leading-6 text-stone-300">
              {@table_detail}
            </p>
          </div>
          <p :if={@finish_notice} id="finish-note" class="mt-2 text-sm text-amber-100">
            {@finish_notice}
          </p>
          <p :if={@disconnect_notice} id="presence-note" role="status" class="match-presence-note">
            {@disconnect_notice}
          </p>
          <p :if={@game_expired} id="expired-game-note" class="match-presence-note">
            {@expiry_notice}
          </p>
          <div
            :if={@game.status == :finished && !@game_expired}
            id="match-result-actions"
            class="mt-5 flex flex-wrap items-center gap-3"
          >
            <button
              :if={show_rematch_button?(@game, @player_side, @rematch_votes)}
              id="rematch-game-button"
              type="button"
              phx-click="rematch-game"
              phx-disable-with="Requesting…"
              class="play-button play-button-primary"
            >
              <.icon name="hero-arrow-path-rounded-square" class="size-4" />
              {rematch_button_label(@mode, @player_side, @rematch_votes)}
            </button>
            <span
              :if={show_rematch_pending?(@game, @player_side, @rematch_votes)}
              id="rematch-pending-indicator"
              class="text-sm text-amber-100"
            >Rematch requested</span>
            <.link navigate={~p"/"} id="result-lobby-link" class="play-button play-button-secondary">Back to lobby</.link>
          </div>
          <p :if={@rematch_notice} id="rematch-note" role="status" class="mt-3 text-sm text-amber-100">
            {@rematch_notice}
          </p>
          <.link
            :if={@game_expired}
            navigate={~p"/"}
            id="expired-lobby-link"
            class="play-button play-button-primary mt-4"
          >Back to lobby</.link>
          <.share_controls
            :if={@awaiting_opponent? && @player_side == :white && !@game_expired}
            share_url={@share_url}
          />
          <button
            :if={@awaiting_opponent? && @player_side == :white && !@game_expired}
            id="cancel-game-button"
            type="button"
            phx-click="cancel-game"
            class="play-button play-button-quiet mt-2"
          >Cancel waiting game</button>
        </section>

        <section id="board-panel" aria-label="Playing table">
          <div id="players-panel" class="match-players" aria-label="Players">
            <.player_strip
              label={player_label(@far_side)}
              side={@far_side}
              token={@players[@far_side]}
              current_token={@player_token}
              connected?={@player_presence[@far_side]}
              current?={
                @turn_side == @far_side && !@awaiting_opponent? && @game.status != :finished &&
                  !@game_expired
              }
              count={pawn_count(@game, @far_side)}
              winner?={@game.winner == @far_side}
            />
          </div>
          <div class="match-board-frame">
            <div id="board-files" class="board-coordinate-row" aria-hidden="true">
              <span></span><span :for={file <- @files}>{file}</span>
            </div>
            <p id="board-keyboard-help" class="sr-only">
              Use arrow keys to explore the board, Home and End for the row, Control Home and Control End for the board. Press Enter or Space to select a pawn or destination. Escape clears your selection. You can explore while waiting or watching.
            </p>
            <div
              id="breakthrough-board"
              phx-hook="BoardDrag"
              role="grid"
              aria-label="Breakthrough board"
              aria-describedby="board-keyboard-help"
              aria-rowcount="8"
              aria-colcount="8"
              data-can-drag={to_string(@can_interact?)}
              data-entry-square={@entry_square_id}
            >
              <div
                :for={{row, row_index} <- Enum.with_index(@board_rows)}
                role="row"
                aria-rowindex={row_index + 1}
                class="board-row"
              >
                <div class="board-rank" aria-hidden="true">{hd(row).rank}</div>
                <div
                  :for={{square, col_index} <- Enum.with_index(row)}
                  role="gridcell"
                  aria-colindex={col_index + 1}
                  class="board-cell"
                >
                  <button
                    id={"square-#{square.id}"}
                    type="button"
                    phx-click="select-square"
                    phx-value-row={square.row}
                    phx-value-col={square.col}
                    tabindex={if square.id == @entry_square_id, do: "0", else: "-1"}
                    aria-pressed={to_string(square.selected?)}
                    aria-disabled={to_string(!@can_interact?)}
                    aria-label={square.accessible_label}
                    data-row={square.row}
                    data-col={square.col}
                    data-selected={to_string(square.selected?)}
                    data-last-move={to_string(square.last_move?)}
                    data-occupied={to_string(square.piece != nil)}
                    data-own-piece={to_string(square.piece == @player_side)}
                    data-legal-move={to_string(square.legal_move?)}
                    data-piece={square.piece_code || "empty"}
                    data-finish-square={to_string(winning_square?(@game, {square.row, square.col}))}
                    class={[
                      "board-square group",
                      square.tone == :light && "board-square-light",
                      square.tone == :dark && "board-square-dark",
                      square.last_move? && "board-square-last",
                      square.selected? && "board-square-selected",
                      square.legal_move? && "board-square-legal"
                    ]}
                  >
                    <span class="sr-only">{square.accessible_label}</span>
                    <img
                      :if={square.piece}
                      src={~p"/images/pawn.svg"}
                      width="56"
                      height="56"
                      alt=""
                      aria-hidden="true"
                      class={["board-pawn", square.piece == :black && "board-pawn-black"]}
                    />
                  </button>
                </div>
              </div>
            </div>
          </div>
          <.player_strip
            label={player_label(@near_side)}
            side={@near_side}
            token={@players[@near_side]}
            current_token={@player_token}
            connected?={@player_presence[@near_side]}
            current?={
              @turn_side == @near_side && !@awaiting_opponent? && @game.status != :finished &&
                !@game_expired
            }
            count={pawn_count(@game, @near_side)}
            winner?={@game.winner == @near_side}
          />
          <p
            id="selection-announcement"
            role="status"
            aria-live="polite"
            aria-atomic="true"
            class="match-selection"
          >
            {@selection_announcement}
          </p>
          <p id="move-announcement" class="sr-only" aria-live="polite" aria-atomic="true">
            {@last_move_announcement}
          </p>
        </section>

        <section
          :if={@show_guidance? && @game.status != :finished && !@game_expired}
          id="match-guidance"
          class="match-guidance"
          aria-labelledby="guidance-title"
        >
          <div>
            <h2 id="guidance-title" class="font-semibold text-stone-100">A race to the far edge.</h2>
            <p class="mt-1 text-sm leading-6 text-stone-300">
              Move one square forward or diagonally into an empty square. Capture diagonally forward. Reach the opposite back rank to win.
            </p>
          </div>
          <button
            id="dismiss-guidance-button"
            type="button"
            phx-click="dismiss-guidance"
            class="match-icon-button"
            aria-label="Dismiss playing hint"
          ><.icon name="hero-x-mark" class="size-4" /></button>
        </section>

        <div class="match-tools">
          <button
            id="game-rules-button"
            type="button"
            phx-click={JS.push_focus() |> JS.push("open-rules")}
            aria-haspopup="dialog"
            class="play-button play-button-quiet"
          ><.icon name="hero-book-open" class="size-4" /> How to play</button>
          <details id="keyboard-instructions" class="match-disclosure">
            <summary>Keyboard controls</summary>
            <p class="text-sm leading-6 text-stone-300">
              Arrow keys explore the board. Enter or Space selects and moves. Escape clears a selection. Home and End move across a row; hold Control to reach the first or last square.
            </p>
          </details>

          <button
            :if={show_resign_button?(@game, @player_side, @players) && !@game_expired}
            id="resign-game-button"
            type="button"
            phx-click={JS.push_focus() |> JS.push("request-resign")}
            aria-haspopup="dialog"
            class="play-button match-resign-button"
          >Resign</button>
        </div>

        <details
          :if={@mode == :pvp && !(@awaiting_opponent? && @player_side == :white) && !@game_expired}
          id="share-details"
          class="match-disclosure match-share-disclosure"
        >
          <summary>Share this game</summary>
          <p class="mt-2 text-sm text-stone-300">
            Send the link to a friend. When both seats are taken, visitors can watch.
          </p>
          <.share_controls share_url={@share_url} />
        </details>

        <section id="recent-moves-panel" class="match-history" aria-labelledby="recent-moves-title">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 id="recent-moves-title" class="display-copy text-xl text-stone-100">Recent moves</h2>
            <span class="text-sm tabular-nums text-stone-400">{@move_count} moves</span>
          </div>
          <ol :if={@move_count > 0} id="recent-moves" class="match-move-list">
            <li :for={move <- @recent_moves} id={"move-#{move.number}"} class="match-move">
              <span class="tabular-nums text-stone-400">{move.number}.</span>
              <span
                class={["match-mini-pawn", move.player == :black && "match-mini-pawn-black"]}
                aria-hidden="true"
              ></span>
              <span class="sr-only">{player_label(move.player)}</span>
              <span>{move.from}</span><.icon
                name={if move.capture?, do: "hero-x-mark", else: "hero-arrow-right"}
                class="size-3 text-stone-400"
              /><span>{move.to}</span>
              <span :if={move.capture?} class="sr-only">capture</span>
            </li>
          </ol>
          <p
            :if={@move_count == 0}
            id="moves-empty-state"
            class="mt-3 text-sm leading-6 text-stone-400"
          >
            {if @game.status == :finished || @game_expired,
              do: "No moves were played.",
              else: "No moves yet. White moves first."}
          </p>
        </section>
        <footer class="match-footer">
          <p id="spectator-count">Spectators: {@spectator_count}</p>
          <p id="turn-value" data-turn={@turn} class="sr-only">{@turn}</p>
          <p>Match <span class="select-all">{@game_id}</span></p>
        </footer>
      </div>
      <.rules_modal :if={@show_rules_modal} />
      <.resign_dialog :if={@show_resign_dialog} opponent_label={player_label(opponent(@player_side))} />
    </Layouts.app>
    """
  end

  defp assign_table_state(socket) do
    assigns = socket.assigns
    game = assigns.game
    near_side = if assigns.player_side == :black, do: :black, else: :white
    waiting? = not seats_ready?(assigns.players)
    squares = List.flatten(assigns.board_rows)

    entry =
      Enum.find(squares, & &1.selected?) ||
        Enum.find(squares, &(&1.piece == assigns.player_side)) || hd(squares)

    move_count = length(game.move_history)

    recent_moves =
      game.move_history
      |> Enum.with_index(1)
      |> Enum.take(-6)
      |> Enum.map(fn {move, number} ->
        %{
          number: number,
          player: move.player,
          from: public_coordinate(move.from),
          to: public_coordinate(move.to),
          capture?: move.capture?
        }
      end)

    assign(socket,
      near_side: near_side,
      far_side: opponent(near_side),
      awaiting_opponent?: waiting?,
      turn_side: game.current_player,
      entry_square_id: entry.id,
      table_title: table_title(game, assigns.player_side, waiting?, assigns.game_expired),
      table_detail: table_detail(game, assigns.player_side, waiting?, assigns.game_expired),
      selection_announcement:
        selection_announcement(
          assigns.selected_square,
          assigns.legal_targets,
          assigns.can_interact?,
          assigns.game_expired || game.status == :finished
        ),
      move_count: move_count,
      recent_moves: recent_moves,
      last_move_announcement: last_move_announcement(List.last(game.move_history))
    )
  end

  defp table_title(_game, _side, _waiting?, true), do: "This game has expired"

  defp table_title(%{status: :finished} = game, side, _waiting?, false),
    do: phase_label(game, side, %{})

  defp table_title(_game, :white, true, false), do: "Invite a friend to play"
  defp table_title(_game, _side, true, false), do: "Waiting for a player"
  defp table_title(%{current_player: side}, side, false, false), do: "Your move"
  defp table_title(game, _side, false, false), do: "#{player_label(game.current_player)} to move"

  defp table_detail(_game, _side, _waiting?, true),
    do:
      "The final position is kept here so you can review it. Return to the lobby to start a new match."

  defp table_detail(%{status: :finished} = game, _side, _waiting?, false),
    do: outcome_description(game)

  defp table_detail(_game, :white, true, false),
    do: "You have White. Share this link to invite a friend to play Black."

  defp table_detail(_game, _side, true, false),
    do: "The game starts when both players have joined."

  defp table_detail(_game, :spectator, false, false),
    do: "You’re watching. Follow each move as the players race to the far edge."

  defp table_detail(%{current_player: side}, side, false, false),
    do: "Select a pawn, then a marked destination. Tap to play, or use the keyboard."

  defp table_detail(_game, _side, false, false),
    do: "Your opponent is choosing a move. You can explore the board while you wait."

  defp outcome_description(%{winner: winner, finish_reason: {:resignation, _}}),
    do: "#{player_label(winner)} wins by resignation."

  defp outcome_description(%{winner: winner} = game) when winner in [:white, :black] do
    case List.last(game.move_history) do
      %{to: {row, _col} = to} when row in [1, 8] ->
        "#{player_label(winner)} reached the back rank on #{public_coordinate(to)}."

      _ ->
        "#{player_label(winner)} captured every opposing pawn."
    end
  end

  defp outcome_description(_game), do: "This game has ended."

  defp selection_announcement(_selected, _targets, _can_interact?, true),
    do: "You can still explore the final board."

  defp selection_announcement(nil, _targets, true, false),
    do: "Choose one of your pawns to see its legal moves."

  defp selection_announcement(nil, _targets, false, false),
    do: "Explore with arrow keys. Moves are available on your turn."

  defp selection_announcement(selected, targets, _can_interact?, false) do
    destinations = targets |> Enum.map(&public_coordinate/1) |> Enum.sort() |> Enum.join(", ")

    if destinations == "",
      do:
        "#{public_coordinate(selected)} is selected. This pawn has no legal moves. Escape clears the selection.",
      else:
        "#{public_coordinate(selected)} selected. Legal destinations: #{destinations}. Escape clears the selection."
  end

  defp square_accessible_label(coord, piece, targets, selected, last_move) do
    [
      accessible_label(coord, piece),
      coord == selected && "selected",
      MapSet.member?(targets, coord) && if(piece, do: "legal capture", else: "legal destination"),
      MapSet.member?(last_move, coord) && "last move"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  defp public_coordinate({row, col}), do: "#{file_label(col)}#{display_rank(row, :white)}"
  defp pawn_count(game, side), do: Enum.count(game.board, fn {_coord, piece} -> piece == side end)
  defp last_move_announcement(nil), do: "No moves yet. White moves first."

  defp last_move_announcement(move),
    do:
      "#{player_label(move.player)} moved from #{public_coordinate(move.from)} to #{public_coordinate(move.to)}#{if move.capture?, do: ", capturing a pawn", else: ""}."

  defp winning_square?(%{winner: winner, finish_reason: nil, move_history: moves}, coord)
       when winner in [:white, :black], do: match?(%{to: ^coord}, List.last(moves))

  defp winning_square?(_game, _coord), do: false
  defp rematch_button_label(:vs_ai, _side, _votes), do: "Play again"

  defp rematch_button_label(_mode, side, votes),
    do:
      if(MapSet.size(votes) > 0 && !MapSet.member?(votes, side),
        do: "Accept rematch",
        else: "Request rematch"
      )

  defp board_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} when index in 1..8 -> {:ok, index}
      _ -> :error
    end
  end

  defp board_index(_value), do: :error

  defp connect_to_game(socket, state) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Breakthrough.PubSub, GameServer.topic(state.id))
      GameManager.track_connection(state.id, socket.assigns.player_token, self())
    else
      {:ok, state}
    end
  end

  defp make_move(socket, to) do
    case GameManager.make_move(
           socket.assigns.game_id,
           socket.assigns.player_token,
           socket.assigns.selected_square,
           to
         ) do
      {:ok, state} ->
        socket
        |> clear_local_selection()
        |> assign_multiplayer_state(state)

      {:error, :spectator} ->
        put_flash(socket, :error, "Spectators cannot move pieces.")

      {:error, :not_your_turn} ->
        put_flash(socket, :error, "Wait for your turn.")

      {:error, :not_ready} ->
        put_flash(socket, :error, "Wait for an opponent to join.")

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "That game is no longer available.")
        |> push_navigate(to: ~p"/")

      {:error, :invalid_move} ->
        put_flash(socket, :error, "That move is not legal.")

      {:error, :game_over} ->
        put_flash(socket, :error, "This game is already finished.")
    end
  end

  defp select_square(socket, coord) do
    socket
    |> assign(
      selected_square: coord,
      legal_targets: MapSet.new(Game.legal_moves(socket.assigns.game, coord))
    )
    |> assign_board_rows()
  end

  defp clear_local_selection(socket) do
    socket
    |> assign(selected_square: nil, legal_targets: MapSet.new())
    |> assign_board_rows()
  end

  defp assign_multiplayer_state(socket, state) do
    player_side = socket.assigns[:player_side] || :spectator

    assign(socket,
      game: state.game,
      show_resign_dialog: socket.assigns.show_resign_dialog && state.game.status != :finished,
      players: state.players,
      mode: state.mode,
      files: file_labels(player_side),
      board_rows:
        board_rows(
          state.game,
          socket.assigns[:legal_targets] || MapSet.new(),
          socket.assigns[:selected_square],
          player_side
        ),
      phase: phase_label(state.game, player_side, state.players),
      turn: turn_label(state.game),
      player_side_label: player_side_label(player_side),
      can_interact?:
        not socket.assigns[:game_expired] and
          can_interact?(state.game, player_side, state.players),
      finish_notice: finish_notice(state.game, player_side),
      rematch_notice: rematch_notice(state, player_side),
      rematch_votes: state.rematch_votes,
      disconnect_notice: disconnect_notice(state),
      player_presence: state.player_presence,
      spectator_count: state.spectator_count,
      share_url: url(~p"/games/#{socket.assigns.game_id}")
    )
    |> assign_table_state()
  end

  defp sync_local_selection(socket) do
    selected_square = socket.assigns.selected_square

    cond do
      is_nil(selected_square) ->
        assign_board_rows(socket)

      not selectable_piece?(socket.assigns, selected_square) ->
        socket |> clear_local_selection() |> assign_board_rows()

      true ->
        legal_targets = MapSet.new(Game.legal_moves(socket.assigns.game, selected_square))
        assign(socket, legal_targets: legal_targets) |> assign_board_rows()
    end
  end

  defp assign_board_rows(socket) do
    assign(socket,
      board_rows:
        board_rows(
          socket.assigns.game,
          socket.assigns.legal_targets,
          socket.assigns.selected_square,
          socket.assigns.player_side
        )
    )
    |> assign_table_state()
  end

  defp selectable_piece?(assigns, coord) do
    assigns.can_interact? and Game.piece_at(assigns.game, coord) == assigns.player_side
  end

  defp move_allowed?(assigns, coord) do
    assigns.can_interact? and not is_nil(assigns.selected_square) and
      MapSet.member?(assigns.legal_targets, coord)
  end

  defp should_clear_selection?(assigns) do
    assigns.can_interact? and not is_nil(assigns.selected_square)
  end

  defp board_rows(game, legal_targets, selected_square, player_side) do
    last_move_squares = last_move_squares(game)

    Enum.map(row_order(player_side), fn row ->
      Enum.map(col_order(player_side), fn col ->
        coord = {row, col}
        piece = Game.piece_at(game, coord)

        %{
          id: square_id(coord),
          row: row,
          col: col,
          rank: Integer.to_string(display_rank(row, player_side)),
          piece: piece,
          piece_code: piece_code(piece),
          tone: square_tone(row, col),
          last_move?: MapSet.member?(last_move_squares, coord),
          selected?: selected_square == coord,
          legal_move?: MapSet.member?(legal_targets, coord),
          accessible_label:
            square_accessible_label(
              coord,
              piece,
              legal_targets,
              selected_square,
              last_move_squares
            )
        }
      end)
    end)
  end

  defp player_side_label(:white), do: "White"
  defp player_side_label(:black), do: "Black"
  defp player_side_label(:spectator), do: "Spectator"

  defp file_label(col), do: <<?a + col - 1>>
  defp file_labels(player_side), do: Enum.map(col_order(player_side), &file_label/1)

  defp square_tone(row, col) when rem(row + col, 2) == 0, do: :light
  defp square_tone(_row, _col), do: :dark
  defp display_rank(row, _player_side), do: Game.board_size() - row + 1
  defp row_order(:black), do: 8..1//-1
  defp row_order(_player_side), do: 1..8
  defp col_order(:black), do: 8..1//-1
  defp col_order(_player_side), do: 1..8
  defp last_move_squares(%{move_history: []}), do: MapSet.new()

  defp last_move_squares(%{move_history: move_history}) do
    %{from: from, to: to} = List.last(move_history)
    MapSet.new([from, to])
  end

  defp square_id({row, col}), do: "#{file_label(col)}#{row}"

  defp can_interact?(%{winner: winner}, _player_side, _players) when winner in [:white, :black],
    do: false

  defp can_interact?(%{current_player: current_player}, player_side, players),
    do:
      player_side in [:white, :black] and seats_ready?(players) and player_side == current_player

  defp phase_label(%{winner: winner}, player_side, _players) when winner in [:white, :black] do
    cond do
      player_side == winner -> "You won"
      player_side in [:white, :black] -> "You lost"
      true -> "#{player_label(winner)} wins"
    end
  end

  defp phase_label(%{status: :finished}, _player_side, _players), do: "Finished"

  defp phase_label(%{status: :not_started}, _player_side, players) do
    if seats_ready?(players) do
      "Waiting on first move"
    else
      "Waiting on opponent to join..."
    end
  end

  defp phase_label(_game, _player_side, _players), do: "In Progress"

  defp disconnect_notice(%{players: players, player_presence: player_presence, game: game}) do
    disconnected_players =
      [:white, :black]
      |> Enum.filter(fn side -> human_player?(players[side]) and not player_presence[side] end)

    case disconnected_players do
      [] ->
        nil

      [side] ->
        "#{player_label(side)} disconnected."

      [_white, _black] when game.move_history != [] ->
        "Both players disconnected. This game will expire soon."

      _both_open_or_unstarted ->
        nil
    end
  end

  defp player_label(:white), do: "White"
  defp player_label(:black), do: "Black"
  defp seats_ready?(players), do: not is_nil(players.white) and not is_nil(players.black)
  defp turn_label(%{status: :finished}), do: "–"
  defp turn_label(%{current_player: current_player}), do: player_label(current_player)

  defp piece_code(nil), do: nil
  defp piece_code(:white), do: "W"
  defp piece_code(:black), do: "B"

  defp show_resign_button?(%{status: status}, player_side, players) do
    status in [:not_started, :in_progress] and player_side in [:white, :black] and
      seats_ready?(players)
  end

  defp show_rematch_button?(%{status: :finished}, player_side, rematch_votes)
       when player_side in [:white, :black],
       do: not MapSet.member?(rematch_votes, player_side)

  defp show_rematch_button?(_game, _player_side, _rematch_votes), do: false

  defp show_rematch_pending?(%{status: :finished}, player_side, rematch_votes)
       when player_side in [:white, :black],
       do: MapSet.member?(rematch_votes, player_side)

  defp show_rematch_pending?(_game, _player_side, _rematch_votes), do: false

  defp game_expired_message(:waiting), do: "No opponent joined before the invitation expired."
  defp game_expired_message(:inactive), do: "Both players left. This game expired."
  defp game_expired_message(:unstarted), do: "No move was made in time. This game expired."
  defp game_expired_message(:stalled), do: "This game expired after a period of inactivity."
  defp game_expired_message(_reason), do: "This game expired."

  defp finish_notice(%{finish_reason: {:resignation, resigning_side}}, player_side) do
    cond do
      player_side == resigning_side -> "You resigned."
      player_side == opponent(resigning_side) -> "#{player_label(resigning_side)} resigned."
      true -> "#{player_label(resigning_side)} resigned."
    end
  end

  defp finish_notice(_game, _player_side), do: nil

  defp rematch_notice(
         %{mode: :pvp, game: %{status: :finished}, rematch_votes: rematch_votes},
         player_side
       ) do
    case MapSet.to_list(rematch_votes) do
      [requesting_side] ->
        rematch_notice_for_player(requesting_side, player_side)

      _ ->
        nil
    end
  end

  defp rematch_notice(_state, _player_side), do: nil

  defp rematch_notice_for_player(requesting_side, player_side) do
    cond do
      player_side == requesting_side ->
        "Waiting for #{player_label(opponent(requesting_side))} to accept rematch."

      true ->
        "#{player_label(requesting_side)} requested a rematch."
    end
  end

  defp opponent(:white), do: :black
  defp opponent(:black), do: :white

  defp human_player?(player_token) when is_binary(player_token), do: true
  defp human_player?(_player_token), do: false

  defp accessible_label({row, col}, nil),
    do: "Empty square #{file_label(col)}#{display_rank(row, :white)}"

  defp accessible_label({row, col}, player) when player in [:white, :black],
    do: "#{player_label(player)} piece on #{file_label(col)}#{display_rank(row, :white)}"
end
