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
     |> assign(:show_rules_modal, false)
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

  def handle_event("open-rules", _params, socket) do
    {:noreply, assign(socket, :show_rules_modal, true)}
  end

  def handle_event("close-rules", _params, socket) do
    {:noreply, assign(socket, :show_rules_modal, false)}
  end

  @impl true
  def handle_info({:lobby_updated, snapshot}, socket) do
    {:noreply, assign_lobby_snapshot(socket, snapshot)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} show_flash_group={false}>
      <section
        :if={Phoenix.Flash.get(@flash, :error)}
        id="home-error-banner"
        class="mx-auto max-w-5xl overflow-hidden rounded-[1.75rem] border border-rose-300/20 bg-[linear-gradient(135deg,rgba(120,24,24,0.92),rgba(55,18,24,0.96))] shadow-[0_24px_80px_rgba(72,12,20,0.38)]"
      >
        <div class="flex items-start gap-4 px-5 py-5 sm:px-6">
          <div class="mt-0.5 flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl border border-rose-200/20 bg-rose-200/10 text-rose-100">
            <.icon name="hero-exclamation-triangle" class="size-5" />
          </div>
          <div class="min-w-0 space-y-1">
            <p class="text-xs font-semibold uppercase tracking-[0.24em] text-rose-100/80">
              Game Unavailable
            </p>
            <p class="text-base font-semibold text-white sm:text-lg">
              {Phoenix.Flash.get(@flash, :error)}
            </p>
            <p class="text-sm leading-6 text-rose-50/80">
              Start a new match or join one from the lobby below.
            </p>
          </div>
        </div>
      </section>

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
            <button
              id="view-rules-button"
              type="button"
              phx-click="open-rules"
              class="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/6 px-5 py-3 text-sm font-semibold text-zinc-100 transition hover:border-white/25 hover:bg-white/10"
            >
              <.icon name="hero-book-open" class="size-4" /> View Rules
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
                :for={game <- @recent_games}
                navigate={~p"/games/#{game.id}"}
                class="flex items-center justify-between rounded-2xl border border-white/8 bg-white/5 px-4 py-3 text-sm text-zinc-300 transition hover:bg-white/10"
              >
                <span class="flex items-center gap-2 font-medium text-white">
                  <span>{game.id}</span>
                  <span
                    :if={game.mode == :vs_ai}
                    class="rounded-full border border-sky-300/30 bg-sky-300/10 px-2 py-0.5 text-[0.65rem] font-semibold uppercase tracking-[0.16em] text-sky-100"
                  >
                    AI
                  </span>
                </span>
                <span class="text-zinc-400">{if game.full?, do: "View game", else: "Join game"}</span>
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

      <div
        :if={@show_rules_modal}
        id="rules-modal"
        class="fixed inset-0 z-50 flex items-center justify-center px-4 py-8"
      >
        <button
          id="rules-modal-backdrop"
          type="button"
          phx-click="close-rules"
          class="absolute inset-0 bg-zinc-950/80 backdrop-blur-sm"
          aria-label="Close rules dialog"
        >
        </button>
        <div class="relative z-10 w-full max-w-2xl rounded-[2rem] border border-white/12 bg-zinc-950/95 p-8 shadow-[0_30px_120px_rgba(0,0,0,0.5)]">
          <div class="flex items-start justify-between gap-6">
            <div class="space-y-3">
              <p class="inline-flex items-center gap-2 rounded-full border border-amber-300/25 bg-amber-300/8 px-3 py-1 text-xs font-semibold uppercase tracking-[0.24em] text-amber-100">
                <span class="h-2 w-2 rounded-full bg-amber-200"></span> Rules
              </p>
              <h2 class="display-copy text-3xl text-white sm:text-4xl">How Breakthrough Works</h2>
              <p class="max-w-xl text-sm leading-7 text-zinc-300 sm:text-base">
                Placeholder rules content goes here. Replace this copy with the final game rules when you are ready.
              </p>
            </div>
            <button
              id="close-rules-button"
              type="button"
              phx-click="close-rules"
              class="inline-flex h-11 w-11 items-center justify-center rounded-full border border-white/10 bg-white/5 text-zinc-200 transition hover:bg-white/10"
              aria-label="Close rules"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="mt-8 rounded-[1.5rem] border border-white/8 bg-white/5 p-6 text-sm leading-7 text-zinc-300">
            Placeholder text for the rules modal body.
          </div>
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
