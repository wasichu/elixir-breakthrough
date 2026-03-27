defmodule BreakthroughWeb.GameLive do
  use BreakthroughWeb, :live_view

  alias Breakthrough.Game

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign_game(Game.new())}
  end

  @impl true
  def handle_event("new-game", _params, socket) do
    {:noreply,
     socket
     |> assign_game(Game.new())
     |> put_flash(:info, "Fresh board loaded. Move resolution is still a stub in v1.")}
  end

  def handle_event("select-square", %{"row" => row, "col" => col}, socket) do
    coord = {String.to_integer(row), String.to_integer(col)}
    game = socket.assigns.game

    socket =
      case game.selected_square do
        ^coord ->
          socket
          |> assign_game(Game.clear_selection(game))
          |> clear_flash(:info)

        nil ->
          select_piece(socket, game, coord)

        selected_square ->
          if selectable_piece?(game, coord) do
            select_piece(socket, game, coord)
          else
            attempt_move(socket, game, selected_square, coord)
          end
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="game-shell" class="grid gap-8 lg:grid-cols-[minmax(0,1.25fr)_20rem]">
        <section class="space-y-6">
          <div class="space-y-4">
            <p class="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs font-semibold uppercase tracking-[0.24em] text-zinc-300">
              <span class="h-2 w-2 rounded-full bg-amber-300"></span> Breakthrough v1
            </p>
            <div class="space-y-3">
              <h1 class="display-copy text-4xl text-white sm:text-5xl">
                A playable shell for the board, without locking you into the rules yet.
              </h1>
              <p class="max-w-2xl text-sm leading-7 text-zinc-300 sm:text-base">
                The board, turn state, and square selection are wired. Legal move generation and win detection are intentionally left as stubs so you can implement them directly in the game module.
              </p>
            </div>
          </div>

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
                  White opens from the near side. Reach the opposite back rank or break the line.
                </p>
              </div>
              <button
                id="new-game-button"
                type="button"
                phx-click="new-game"
                class="inline-flex items-center gap-2 rounded-full border border-amber-300/40 bg-amber-300/10 px-4 py-2 text-sm font-semibold text-amber-100 transition hover:border-amber-200 hover:bg-amber-300/20"
              >
                <.icon name="hero-arrow-path" class="size-4" /> Reset
              </button>
            </div>

            <div class="overflow-hidden rounded-[1.75rem] border border-white/8 bg-zinc-950/70 p-3 sm:p-4">
              <div class="mb-3 grid grid-cols-[1.5rem_repeat(8,minmax(0,1fr))] gap-2 text-center text-[0.65rem] font-semibold uppercase tracking-[0.2em] text-zinc-500">
                <span></span>
                <span :for={file <- @files}>{file}</span>
              </div>

              <div id="breakthrough-board" class="space-y-2">
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
                    data-selected={to_string(square.selected?)}
                    data-occupied={to_string(square.piece != nil)}
                    data-piece={square.piece_code || "empty"}
                    class={[
                      "group aspect-square rounded-2xl border text-sm font-semibold transition duration-150 ease-out focus:outline-none focus:ring-2 focus:ring-amber-200/70",
                      square.tone == :light &&
                        "border-amber-950/30 bg-[#9f7a50] text-stone-950 hover:bg-[#af8960]",
                      square.tone == :dark &&
                        "border-[#2d1f1a]/50 bg-[#5c4033] text-stone-100 hover:bg-[#6a4a3b]",
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
              </div>
              <span class="inline-flex h-11 w-11 items-center justify-center rounded-full border border-emerald-300/25 bg-emerald-300/10 text-emerald-200">
                <.icon name="hero-bolt" class="size-5" />
              </span>
            </div>

            <dl class="mt-5 space-y-4 text-sm text-zinc-300">
              <div class="rounded-2xl border border-white/8 bg-black/20 p-4">
                <dt class="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-500">Turn</dt>
                <dd id="turn-value" data-turn={@turn} class="mt-1 text-lg text-white">{@turn}</dd>
              </div>
              <div
                id="selected-piece-panel"
                data-selected={@selected_square_id || "none"}
                class="rounded-2xl border border-white/8 bg-black/20 p-4"
              >
                <dt class="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-500">
                  Selected Square
                </dt>
                <dd
                  id="selected-square-value"
                  data-selected={@selected_square_id || "none"}
                  class="mt-1 text-lg text-white"
                >
                  {@selected_square_id || "None"}
                </dd>
              </div>
              <div class="rounded-2xl border border-white/8 bg-black/20 p-4">
                <dt class="text-xs font-semibold uppercase tracking-[0.22em] text-zinc-500">
                  Legal Moves
                </dt>
                <dd
                  id="legal-move-count"
                  data-count={length(@legal_move_ids)}
                  class="mt-1 text-lg text-white"
                >
                  {length(@legal_move_ids)}
                </dd>
              </div>
            </dl>
          </section>

          <section
            id="stub-notes-panel"
            class="rounded-[2rem] border border-white/10 bg-black/25 p-5 backdrop-blur"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-zinc-400">Stub Notes</p>
            <ul class="mt-4 space-y-3 text-sm leading-6 text-zinc-300">
              <li class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3">
                `Breakthrough.Game.legal_moves/2` currently returns an empty list.
              </li>
              <li class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3">
                `Breakthrough.Game.move/3` currently reports a not implemented error.
              </li>
              <li class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3">
                The LiveView is already wired to call those functions when you click from one square to another.
              </li>
            </ul>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp select_piece(socket, game, coord) do
    case Game.select_square(game, coord) do
      {:ok, next_game} ->
        socket
        |> assign_game(next_game)
        |> clear_flash(:info)

      {:error, :invalid_selection} ->
        put_flash(socket, :info, "Select one of the current turn's pieces to start a move.")
    end
  end

  defp attempt_move(socket, game, from, to) do
    case Game.move(game, from, to) do
      {:ok, next_game} ->
        socket
        |> assign_game(next_game)
        |> clear_flash(:info)
    end
  end

  defp assign_game(socket, game) do
    legal_move_lookup =
      case game.selected_square do
        nil -> MapSet.new()
        coord -> game |> Game.legal_moves(coord) |> MapSet.new()
      end

    assign(socket,
      game: game,
      files: Enum.map(1..Game.board_size(), &file_label/1),
      board_rows: board_rows(game, legal_move_lookup),
      selected_square_id: maybe_square_id(game.selected_square),
      legal_move_ids: Enum.map(legal_move_lookup, &square_id/1),
      phase: phase_label(game),
      turn: player_label(game.current_turn)
    )
  end

  defp selectable_piece?(game, coord) do
    case Game.piece_at(game, coord) do
      player when player in [:white, :black] -> player == game.current_turn
      _ -> false
    end
  end

  defp board_rows(game, legal_move_lookup) do
    Enum.map(1..8, fn row ->
      Enum.map(1..8, fn col ->
        coord = {row, col}
        piece = Game.piece_at(game, coord)

        %{
          id: square_id(coord),
          row: row,
          col: col,
          rank: Integer.to_string(display_rank(row)),
          piece: piece,
          piece_code: piece_code(piece),
          tone: square_tone(row, col),
          selected?: game.selected_square == coord,
          legal_move?: MapSet.member?(legal_move_lookup, coord),
          accessible_label: accessible_label(coord, piece)
        }
      end)
    end)
  end

  defp file_label(col), do: <<?a + col - 1>>

  defp square_tone(row, col) when rem(row + col, 2) == 0, do: :light
  defp square_tone(_row, _col), do: :dark
  defp display_rank(row), do: Game.board_size() - row + 1

  defp square_id({row, col}), do: "#{file_label(col)}#{row}"
  defp maybe_square_id(nil), do: nil
  defp maybe_square_id(coord), do: square_id(coord)

  defp phase_label(%{winner: winner}) when winner in [:white, :black],
    do: "#{player_label(winner)} wins"

  defp phase_label(%{status: :finished}), do: "Finished"
  defp phase_label(_game), do: "Opening"

  defp player_label(:white), do: "White"
  defp player_label(:black), do: "Black"

  defp piece_code(nil), do: nil
  defp piece_code(:white), do: "W"
  defp piece_code(:black), do: "B"

  defp accessible_label({row, col}, nil), do: "Empty square #{file_label(col)}#{row}"

  defp accessible_label({row, col}, player) when player in [:white, :black],
    do: "#{player_label(player)} piece on #{file_label(col)}#{row}"
end
