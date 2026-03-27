defmodule BreakthroughWeb.GameLive do
  use BreakthroughWeb, :live_view

  alias Breakthrough.Game
  alias Breakthrough.Games.GameManager
  alias Breakthrough.Games.GameServer

  @impl true
  def mount(%{"id" => game_id}, %{"player_token" => player_token}, socket) do
    socket =
      socket
      |> assign(:current_scope, nil)
      |> assign(:game_id, game_id)
      |> assign(:player_token, player_token)

    case GameManager.join_game(game_id, player_token) do
      {:ok, player_side, state} ->
        state =
          if connected?(socket) do
            Phoenix.PubSub.subscribe(Breakthrough.PubSub, GameServer.topic(game_id))
            {:ok, state} = GameManager.track_connection(game_id, player_token, self())
            state
          else
            state
          end

        {:ok,
         socket
         |> assign(:player_side, player_side)
         |> assign(:selected_square, nil)
         |> assign(:legal_targets, MapSet.new())
         |> assign(:copy_status, "Copy")
         |> assign(:game_expired, false)
         |> assign_multiplayer_state(state)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That game is no longer available.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("select-square", %{"row" => row, "col" => col}, socket) do
    coord = {String.to_integer(row), String.to_integer(col)}

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
  end

  def handle_event("resign-game", _params, socket) do
    case GameManager.resign(socket.assigns.game_id, socket.assigns.player_token) do
      {:ok, state} ->
        {:noreply,
         socket
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

  @impl true
  def handle_info({:game_expired, :inactive}, socket) do
    {:noreply,
     socket
     |> clear_local_selection()
     |> assign(
       game_expired: true,
       phase: "Expired",
       disconnect_notice: "Both players left. This game expired.",
       can_interact?: false
     )}
  end

  @impl true
  def handle_info({:rematch_created, game_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="game-shell" class="grid gap-8 lg:grid-cols-[minmax(0,1.25fr)_20rem]">
        <section>
          <section
            id="board-panel"
            class="rounded-[2rem] border border-white/10 bg-black/25 p-4 shadow-[0_30px_80px_rgba(0,0,0,0.28)] backdrop-blur sm:p-6"
          >
            <div class="mb-4 flex items-center justify-between gap-4">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.24em] text-zinc-400">
                  Game Board
                </p>
                <p class="mt-1 text-sm text-zinc-300">
                  White and Black can join by URL. Extra visitors watch as spectators.
                </p>
              </div>
              <button
                :if={show_resign_button?(@game, @player_side)}
                id="resign-game-button"
                type="button"
                phx-click="resign-game"
                class="inline-flex items-center gap-2 rounded-full border border-rose-300/40 bg-rose-300/10 px-4 py-2 text-sm font-semibold text-rose-100 transition hover:border-rose-200 hover:bg-rose-300/20"
              >
                <.icon name="hero-flag" class="size-4" /> Resign
              </button>
              <button
                :if={show_rematch_button?(@game, @player_side, @rematch_votes)}
                id="rematch-game-button"
                type="button"
                phx-click="rematch-game"
                class="inline-flex items-center gap-2 rounded-full border border-emerald-300/40 bg-emerald-300/10 px-4 py-2 text-sm font-semibold text-emerald-100 transition hover:border-emerald-200 hover:bg-emerald-300/20"
              >
                <.icon name="hero-arrow-path-rounded-square" class="size-4" /> Rematch
              </button>
              <div
                :if={show_rematch_pending?(@game, @player_side, @rematch_votes)}
                id="rematch-pending-indicator"
                class="inline-flex items-center gap-2 rounded-full border border-emerald-300/20 bg-emerald-300/8 px-4 py-2 text-sm font-semibold text-emerald-100"
              >
                <.icon name="hero-check-circle" class="size-4" /> Rematch requested
              </div>
            </div>

            <div class="overflow-hidden rounded-[1.75rem] border border-white/8 bg-zinc-950/70 p-3 sm:p-4">
              <div class="mb-3 grid grid-cols-[1.5rem_repeat(8,minmax(0,1fr))] gap-2 text-center text-[0.65rem] font-semibold uppercase tracking-[0.2em] text-zinc-500">
                <span></span>
                <span :for={file <- @files}>{file}</span>
              </div>

              <div
                id="breakthrough-board"
                phx-hook="BoardDrag"
                class="space-y-2"
                data-can-drag={to_string(@can_interact?)}
              >
                <div
                  :for={row <- @board_rows}
                  class="grid grid-cols-[1.5rem_repeat(8,minmax(0,1fr))] gap-2"
                >
                  <div class="flex items-center justify-center text-[0.65rem] font-semibold uppercase tracking-[0.2em] text-zinc-500">
                    {hd(row).rank}
                  </div>
                  <button
                    :for={square <- row}
                    id={"square-#{square.id}"}
                    type="button"
                    phx-click="select-square"
                    phx-value-row={square.row}
                    phx-value-col={square.col}
                    aria-pressed={to_string(square.selected?)}
                    disabled={!@can_interact?}
                    data-row={square.row}
                    data-col={square.col}
                    data-selected={to_string(square.selected?)}
                    data-last-move={to_string(square.last_move?)}
                    data-occupied={to_string(square.piece != nil)}
                    data-own-piece={to_string(square.piece == @player_side)}
                    data-legal-move={to_string(square.legal_move?)}
                    data-piece={square.piece_code || "empty"}
                    class={[
                      "group aspect-square rounded-2xl border text-sm font-semibold transition duration-150 ease-out focus:outline-none focus:ring-2 focus:ring-amber-200/70",
                      square.tone == :light &&
                        "border-amber-950/30 bg-[#9f7a50] text-stone-950 hover:bg-[#af8960]",
                      square.tone == :dark &&
                        "border-[#2d1f1a]/50 bg-[#5c4033] text-stone-100 hover:bg-[#6a4a3b]",
                      square.last_move? &&
                        "ring-2 ring-sky-300/70 ring-offset-0 shadow-[0_0_0_1px_rgba(125,211,252,0.25)]",
                      square.selected? &&
                        "scale-[0.96] border-amber-200 bg-amber-200 text-zinc-950 shadow-[0_0_0_1px_rgba(251,191,36,0.3)]",
                      square.legal_move? && "ring-2 ring-emerald-300/60 ring-offset-0"
                    ]}
                  >
                    <span class="sr-only">{square.accessible_label}</span>
                    <span :if={square.piece} class="inline-flex items-center justify-center">
                      <img
                        src={~p"/images/pawn.svg"}
                        alt=""
                        aria-hidden="true"
                        class={[
                          "h-12 w-12 transition duration-150 ease-out group-hover:scale-105 sm:h-14 sm:w-14",
                          square.piece == :white &&
                            "drop-shadow-[0_1px_1px_rgba(0,0,0,0.9)]",
                          square.piece == :black &&
                            "brightness-[0.32] contrast-[1.2] saturate-0 drop-shadow-[0_1px_0_rgba(255,244,220,0.22)]"
                        ]}
                      />
                    </span>
                  </button>
                </div>
              </div>
            </div>
            <div
              :if={@board_prompt}
              id="board-prompt"
              class="mt-4 rounded-2xl border border-white/8 bg-white/6 px-4 py-3 text-center text-sm font-semibold tracking-[0.08em] text-zinc-100"
            >
              {@board_prompt}
            </div>
          </section>
        </section>

        <aside class="space-y-4">
          <section
            id="game-status-panel"
            class="rounded-[2rem] border border-white/10 bg-white/6 p-5 backdrop-blur"
          >
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.24em] text-zinc-400">
                  Match Status
                </p>
                <p id="phase-value" data-phase={@phase} class="mt-2 text-2xl text-white">
                  {@phase}
                </p>
                <p :if={@finish_notice} id="finish-note" class="mt-2 text-sm text-amber-100">
                  {@finish_notice}
                </p>
                <p :if={@rematch_notice} id="rematch-note" class="mt-2 text-sm text-emerald-100">
                  {@rematch_notice}
                </p>
                <p :if={@disconnect_notice} id="presence-note" class="mt-2 text-sm text-amber-100">
                  {@disconnect_notice}
                </p>
              </div>
              <span class="inline-flex h-11 w-11 items-center justify-center rounded-full border border-emerald-300/25 bg-emerald-300/10 text-emerald-200">
                <.icon name="hero-users" class="size-5" />
              </span>
            </div>

            <dl class="mt-5 space-y-4 text-sm text-zinc-300">
              <div class="rounded-2xl border border-white/8 bg-black/20 p-4">
                <dt class="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-500">
                  You Are
                </dt>
                <dd id="player-side-value" data-side={@player_side} class="mt-1 text-lg text-white">
                  {@player_side_label}
                </dd>
              </div>
              <div class="rounded-2xl border border-white/8 bg-black/20 p-4">
                <dt class="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-500">Turn</dt>
                <dd id="turn-value" data-turn={@turn} class="mt-1 text-lg text-white">{@turn}</dd>
              </div>
              <div class="rounded-2xl border border-white/8 bg-black/20 p-4">
                <dt class="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-500">
                  Share Link
                </dt>
                <dd
                  id="share-link-panel"
                  phx-hook="ShareLink"
                  phx-update="ignore"
                  data-share-url={@share_url}
                  class="mt-2 space-y-3"
                >
                  <input
                    id="game-share-link"
                    type="text"
                    readonly
                    value={@share_url}
                    class="w-full rounded-xl border border-white/10 bg-zinc-950/80 px-3 py-2 text-sm text-amber-100"
                  />
                  <button
                    id="copy-link-button"
                    type="button"
                    phx-hook="CopyText"
                    data-copy-target="#game-share-link"
                    class="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2 text-sm font-semibold text-zinc-200 transition hover:bg-white/10"
                  >
                    <.icon name="hero-clipboard-document" class="size-4" />
                    <span>{@copy_status}</span>
                  </button>
                </dd>
              </div>
            </dl>
          </section>

          <section
            id="players-panel"
            class="rounded-[2rem] border border-white/10 bg-black/25 p-5 backdrop-blur"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-zinc-400">Seats</p>
            <div class="mt-4 space-y-3 text-sm text-zinc-300">
              <div
                id="white-seat-status"
                class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3"
              >
                White: {seat_status(@players.white, @player_token, @player_presence.white)}
              </div>
              <div
                id="black-seat-status"
                class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3"
              >
                Black: {seat_status(@players.black, @player_token, @player_presence.black)}
              </div>
              <div id="spectator-count" class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3">
                Spectators: {@spectator_count}
              </div>
              <div class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3">
                Move no: {length(@game.move_history)}
              </div>
            </div>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
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
      selected_square_id: maybe_square_id(socket.assigns[:selected_square]),
      phase: phase_label(state.game, player_side, state.players),
      turn: player_label(state.game.current_player),
      player_side_label: player_side_label(player_side),
      can_interact?:
        not socket.assigns[:game_expired] and
          can_interact?(state.game, player_side),
      board_prompt: board_prompt(state.game, player_side),
      finish_notice: finish_notice(state.game, player_side),
      rematch_notice: rematch_notice(state, player_side),
      rematch_votes: state.rematch_votes,
      disconnect_notice: disconnect_notice(state),
      player_presence: state.player_presence,
      spectator_count: state.spectator_count,
      share_url: url(~p"/games/#{socket.assigns.game_id}")
    )
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
        ),
      selected_square_id: maybe_square_id(socket.assigns.selected_square)
    )
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
          accessible_label: accessible_label(coord, piece)
        }
      end)
    end)
  end

  defp seat_status(:ai, _current_token, _connected?), do: "AI"
  defp seat_status(nil, _current_token, _connected?), do: "Open"
  defp seat_status(token, token, _connected?), do: "You"
  defp seat_status(_token, _current_token, true), do: "Claimed"
  defp seat_status(_token, _current_token, false), do: "Disconnected"

  defp player_side_label(:white), do: "White"
  defp player_side_label(:black), do: "Black"
  defp player_side_label(:spectator), do: "Spectator"

  defp file_label(col), do: <<?a + col - 1>>
  defp file_labels(:black), do: Enum.map(8..1//-1, &display_file_label(&1, :black))

  defp file_labels(_player_side),
    do: Enum.map(1..Game.board_size(), &display_file_label(&1, :white))

  defp square_tone(row, col) when rem(row + col, 2) == 0, do: :light
  defp square_tone(_row, _col), do: :dark
  defp display_rank(row, :black), do: row
  defp display_rank(row, _player_side), do: Game.board_size() - row + 1
  defp display_file_label(col, :black), do: file_label(Game.board_size() - col + 1)
  defp display_file_label(col, _player_side), do: file_label(col)
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
  defp maybe_square_id(nil), do: nil
  defp maybe_square_id(coord), do: square_id(coord)
  defp can_interact?(%{winner: winner}, _player_side) when winner in [:white, :black], do: false

  defp can_interact?(%{current_player: current_player}, player_side),
    do: player_side in [:white, :black] and player_side == current_player

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
        "Both players disconnected. This game will expire in 5 seconds."

      _both_open_or_unstarted ->
        nil
    end
  end

  defp player_label(:white), do: "White"
  defp player_label(:black), do: "Black"
  defp seats_ready?(players), do: not is_nil(players.white) and not is_nil(players.black)

  defp piece_code(nil), do: nil
  defp piece_code(:white), do: "W"
  defp piece_code(:black), do: "B"

  defp show_resign_button?(%{status: status}, player_side) do
    status == :in_progress and player_side in [:white, :black]
  end

  defp show_rematch_button?(%{status: :finished}, player_side, rematch_votes)
       when player_side in [:white, :black],
       do: not MapSet.member?(rematch_votes, player_side)

  defp show_rematch_button?(_game, _player_side, _rematch_votes), do: false

  defp show_rematch_pending?(%{status: :finished}, player_side, rematch_votes)
       when player_side in [:white, :black],
       do: MapSet.member?(rematch_votes, player_side)

  defp show_rematch_pending?(_game, _player_side, _rematch_votes), do: false

  defp board_prompt(%{winner: winner}, player_side) when winner in [:white, :black] do
    cond do
      player_side == winner -> "You won"
      player_side in [:white, :black] -> "You lost"
      true -> nil
    end
  end

  defp board_prompt(%{current_player: current_player}, player_side)
       when player_side in [:white, :black] do
    if player_side == current_player, do: "Your move", else: "Opponent's move"
  end

  defp board_prompt(_game, _player_side), do: nil

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

  defp accessible_label({row, col}, nil), do: "Empty square #{file_label(col)}#{row}"

  defp accessible_label({row, col}, player) when player in [:white, :black],
    do: "#{player_label(player)} piece on #{file_label(col)}#{row}"
end
