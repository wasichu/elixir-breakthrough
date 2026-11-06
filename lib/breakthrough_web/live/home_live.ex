defmodule BreakthroughWeb.HomeLive do
  use BreakthroughWeb, :live_view

  alias Breakthrough.Games.GameManager
  import BreakthroughWeb.RulesComponents, only: [rules_modal: 1]

  @impl true
  def mount(_params, %{"player_token" => player_token}, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Breakthrough.PubSub, Breakthrough.Games.GameTracker.topic())
    end

    {:ok,
     socket
     |> assign(:player_token, player_token)
     |> assign(:current_scope, nil)
     |> assign(:show_rules_modal, false)
     |> assign(:creation_notice, nil)
     |> assign_lobby_snapshot(GameManager.lobby_snapshot())}
  end

  @impl true
  def handle_event("new-game", _params, socket) do
    create_game(socket, :pvp)
  end

  def handle_event("new-ai-game", _params, socket) do
    create_game(socket, :vs_ai)
  end

  def handle_event("cancel-current-game", %{"id" => game_id}, socket) do
    result =
      with {:ok, %{id: ^game_id}} <- GameManager.get_created_game(socket.assigns.player_token) do
        GameManager.cancel_game(game_id, socket.assigns.player_token)
      end

    socket = socket |> assign(:creation_notice, nil) |> assign_created_game()

    message =
      case result do
        :ok ->
          "Waiting game cancelled. You can start a new match."

        {:error, :not_waiting} ->
          "Your opponent has joined. Return to the game to play or resign."

        _ ->
          if socket.assigns.created_game do
            "That waiting game is no longer available to cancel. Your current game is shown below."
          else
            "That waiting game has already ended. You can start a new match."
          end
      end

    {:noreply, put_flash(socket, :info, message)}
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
      <p
        :if={Phoenix.Flash.get(@flash, :info)}
        id="home-info-banner"
        role="status"
        class="mx-auto max-w-5xl rounded-xl border border-amber-200/20 bg-amber-200/5 px-5 py-4 text-sm leading-6 text-amber-100"
      >
        {Phoenix.Flash.get(@flash, :info)}
      </p>
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

      <div id="home-lobby" class="mx-auto max-w-5xl space-y-12 sm:space-y-16">
        <div class="grid items-start gap-10 lg:grid-cols-[1.5fr_1fr] lg:gap-16">
          <section id="start-playing" class="space-y-6 py-2 sm:py-6" aria-labelledby="home-title">
            <h1 id="home-title" class="display-copy text-5xl text-white sm:text-6xl">Breakthrough</h1>
            <p class="max-w-lg text-lg leading-8 text-zinc-300">
              Race your pawns across the board and be the first to breakthrough.
            </p>
            <section
              :if={@created_game}
              id="current-created-game"
              data-game-id={@created_game.id}
              aria-labelledby="current-game-title"
              class="rounded-xl border border-white/15 bg-white/3 p-5"
            >
              <h2 id="current-game-title" class="display-copy text-2xl text-white">
                {created_game_title(@created_game)}
              </h2>
              <p class="mt-2 text-sm leading-6 text-zinc-300">
                <%= if @created_game.waiting? do %>
                  You can have one active game at a time. Return to invite a friend, or cancel this waiting game before starting another.
                <% else %>
                  Finish or resign from this game before creating another. You can return to it below.
                <% end %>
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <.link
                  id="return-to-current-game"
                  navigate={~p"/games/#{@created_game.id}"}
                  class="play-button play-button-secondary"
                >Return to game</.link>
                <button
                  :if={@created_game.waiting?}
                  id="cancel-current-game-button"
                  type="button"
                  phx-click="cancel-current-game"
                  phx-value-id={@created_game.id}
                  phx-disable-with="Cancelling…"
                  class="play-button play-button-quiet"
                >Cancel waiting game</button>
              </div>
            </section>
            <div class="flex flex-col items-start gap-3 pt-2">
              <button
                id="create-game-button"
                type="button"
                phx-click="new-game"
                phx-disable-with={
                  if @created_game, do: "Checking current game…", else: "Creating match…"
                }
                class="play-button play-button-primary"
              >
                <.icon name="hero-user-group" class="size-5" /> New Multiplayer Game
                <.icon name="hero-arrow-right" class="ml-2 size-4" />
              </button>
              <div class="flex flex-wrap gap-2">
                <button
                  id="create-ai-game-button"
                  type="button"
                  phx-click="new-ai-game"
                  phx-disable-with={
                    if @created_game, do: "Checking current game…", else: "Creating match…"
                  }
                  class="play-button play-button-secondary"
                >
                  <.icon name="hero-cpu-chip" class="size-4" /> Play vs AI
                </button>
                <button
                  id="view-rules-button"
                  type="button"
                  phx-click={JS.push_focus() |> JS.push("open-rules")}
                  aria-haspopup="dialog"
                  aria-expanded={to_string(@show_rules_modal)}
                  class="play-button play-button-quiet"
                >
                  <.icon name="hero-book-open" class="size-4" /> View Rules
                </button>
              </div>
              <p
                :if={@creation_notice}
                id="new-game-notice"
                role="status"
                class="max-w-prose text-sm leading-6 text-amber-100"
              >
                {@creation_notice}
              </p>
            </div>
          </section>

          <aside class="border-t border-white/12 pt-6 lg:mt-8" aria-labelledby="how-it-works-title">
            <h2 id="how-it-works-title" class="display-copy text-2xl text-white">How It Works</h2>
            <ol class="mt-5 list-decimal space-y-4 pl-5 text-sm leading-7 text-zinc-300 marker:text-amber-200">
              <li class="pl-2">Create a match to claim White.</li>
              <li class="pl-2">Send the game URL to another player so they can claim Black.</li>
              <li class="pl-2">Extra visitors become spectators and see every move live.</li>
            </ol>
          </aside>
        </div>

        <section id="lobby-panel" class="border-t border-white/12 pt-7" aria-labelledby="lobby-title">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 id="lobby-title" class="display-copy text-3xl text-white">Lobby</h2>
            <p class="flex items-center gap-2 text-sm text-zinc-400">
              <span class="size-1.5 rounded-full bg-emerald-300" aria-hidden="true"></span>
              Active games:
              <span id="active-games-count" class="tabular-nums text-zinc-100">{@active_games_count}</span>
            </p>
          </div>
          <div id="recent-games" class="mt-5 divide-y divide-white/10">
            <.link
              :for={game <- @recent_games}
              id={"lobby-game-#{game.id}"}
              navigate={~p"/games/#{game.id}"}
              class="lobby-game flex min-h-16 items-center justify-between gap-4 py-4 text-sm"
            >
              <span class="flex min-w-0 items-center gap-3 font-medium text-white">
                <.icon name="hero-squares-2x2" class="size-5 shrink-0 text-amber-200/80" />
                <span class="truncate">{game.id}</span>
                <span
                  :if={game.mode == :vs_ai}
                  id={"lobby-ai-#{game.id}"}
                  class="rounded border border-sky-300/25 px-2 py-0.5 text-xs text-sky-100"
                >AI</span>
              </span>
              <span class="flex shrink-0 items-center gap-2 text-zinc-300">
                {if game.full? || Map.get(game, :status) == :finished,
                  do: "View game",
                  else: "Join game"}
                <.icon name="hero-arrow-up-right" class="size-4" />
              </span>
            </.link>
            <p
              :if={@recent_games == []}
              id="lobby-empty-state"
              class="py-8 text-sm leading-7 text-zinc-400"
            >
              No active games yet.
            </p>
          </div>
        </section>
      </div>

      <.rules_modal :if={@show_rules_modal} />
    </Layouts.app>
    """
  end

  defp create_game(socket, mode) do
    case GameManager.create_game(mode: mode, creator_token: socket.assigns.player_token) do
      {:ok, game_id} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}

      {:error, {:active_game, _game_id}} ->
        socket = assign_created_game(socket)

        message =
          if socket.assigns.created_game do
            "A new game wasn’t created because you already have an active game. Return to your game, or cancel it if you’re still waiting for an opponent."
          else
            "Your previous game just ended. Please try creating a new game."
          end

        {:noreply, assign(socket, :creation_notice, message)}
    end
  end

  defp assign_lobby_snapshot(socket, snapshot) do
    assign(socket,
      active_games_count: snapshot.active_games_count,
      recent_games: snapshot.recent_games
    )
    |> assign_created_game()
  end

  defp assign_created_game(socket) do
    created_game =
      case GameManager.get_created_game(socket.assigns.player_token) do
        {:ok, state} ->
          %{
            id: state.id,
            mode: state.mode,
            waiting?: state.game.status == :not_started && is_nil(state.players.black)
          }

        {:error, :not_found} ->
          nil
      end

    assign(socket,
      created_game: created_game,
      creation_notice: if(created_game, do: socket.assigns.creation_notice, else: nil)
    )
  end

  defp created_game_title(%{waiting?: true}), do: "Your game is waiting for an opponent"
  defp created_game_title(%{mode: :vs_ai}), do: "You have an AI game in progress"
  defp created_game_title(_game), do: "You have a multiplayer game in progress"
end
