defmodule BreakthroughWeb.HomeLive do
  use BreakthroughWeb, :live_view

  alias Breakthrough.Games.GameManager

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Breakthrough.PubSub, Breakthrough.Games.GameTracker.topic())
    end

    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign_lobby_snapshot(GameManager.lobby_snapshot())}
  end

  @impl true
  def handle_event("new-game", _params, socket) do
    {:ok, game_id} = GameManager.create_game()
    {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}
  end

  def handle_event("new-ai-game", _params, socket) do
    {:ok, game_id} = GameManager.create_game(mode: :vs_ai)
    {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}
  end

  @impl true
  def handle_info({:lobby_updated, snapshot}, socket) do
    {:noreply, assign_lobby_snapshot(socket, snapshot)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto grid max-w-5xl gap-8 lg:grid-cols-[1.4fr_0.8fr]">
        <section class="space-y-5 rounded-[2rem] border border-white/10 bg-black/25 p-8 backdrop-blur">
          <p class="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs font-semibold uppercase tracking-[0.24em] text-zinc-300">
            <span class="h-2 w-2 rounded-full bg-emerald-300"></span> Multiplayer v1
          </p>
          <h1 class="display-copy text-4xl text-white sm:text-5xl">
            Start a game and share the URL.
          </h1>
          <p class="max-w-2xl text-sm leading-7 text-zinc-300 sm:text-base">
            The first visitor joins as White, the second joins as Black, and everyone after that watches as a spectator.
          </p>
          <div class="flex flex-wrap gap-3">
            <button
              id="create-game-button"
              type="button"
              phx-click="new-game"
              class="inline-flex items-center gap-2 rounded-full border border-amber-300/40 bg-amber-300/10 px-5 py-3 text-sm font-semibold text-amber-100 transition hover:border-amber-200 hover:bg-amber-300/20"
            >
              <.icon name="hero-user-group" class="size-4" /> New Multiplayer Game
            </button>
            <button
              id="create-ai-game-button"
              type="button"
              phx-click="new-ai-game"
              class="inline-flex items-center gap-2 rounded-full border border-sky-300/40 bg-sky-300/10 px-5 py-3 text-sm font-semibold text-sky-100 transition hover:border-sky-200 hover:bg-sky-300/20"
            >
              <.icon name="hero-cpu-chip" class="size-4" /> Play vs AI
            </button>
          </div>
        </section>

        <div class="space-y-4">
          <aside class="rounded-[2rem] border border-white/10 bg-white/6 p-6 backdrop-blur">
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-zinc-400">
              How It Works
            </p>
            <ul class="mt-4 space-y-3 text-sm leading-6 text-zinc-300">
              <li class="rounded-2xl border border-white/8 bg-black/20 px-4 py-3">
                Open the new game in your browser to claim White.
              </li>
              <li class="rounded-2xl border border-white/8 bg-black/20 px-4 py-3">
                Open the same URL in another browser or private window to claim Black.
              </li>
              <li class="rounded-2xl border border-white/8 bg-black/20 px-4 py-3">
                Anyone else visiting the same link becomes a spectator and sees live updates.
              </li>
            </ul>
          </aside>

          <aside class="rounded-[2rem] border border-white/10 bg-black/25 p-6 backdrop-blur">
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-zinc-400">Lobby</p>
            <div class="mt-4 rounded-2xl border border-white/8 bg-white/5 px-4 py-3 text-sm text-zinc-300">
              Active games:
              <span id="active-games-count" class="font-semibold text-white">
                {@active_games_count}
              </span>
            </div>
            <div class="mt-4 space-y-3">
              <.link
                :for={game_id <- @recent_games}
                navigate={~p"/games/#{game_id}"}
                class="flex items-center justify-between rounded-2xl border border-white/8 bg-white/5 px-4 py-3 text-sm text-zinc-300 transition hover:bg-white/10"
              >
                <span class="font-medium text-white">{game_id}</span>
                <span class="text-zinc-400">Join game</span>
              </.link>
              <div
                :if={@recent_games == []}
                class="rounded-2xl border border-white/8 bg-white/5 px-4 py-3 text-sm text-zinc-400"
              >
                No active games yet.
              </div>
            </div>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_lobby_snapshot(socket, snapshot) do
    assign(socket,
      active_games_count: snapshot.active_games_count,
      recent_games: snapshot.recent_games
    )
  end
end
