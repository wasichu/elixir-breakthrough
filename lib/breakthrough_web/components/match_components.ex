defmodule BreakthroughWeb.MatchComponents do
  use BreakthroughWeb, :html

  attr :share_url, :string, required: true

  def share_controls(assigns) do
    ~H"""
    <div
      id="share-link-panel"
      phx-hook="ShareLink"
      phx-update="ignore"
      data-share-url={@share_url}
      class="match-share-controls"
    >
      <.input
        id="game-share-link"
        name="share_url"
        aria-label="Game share link"
        type="text"
        readonly
        value={@share_url}
        class="match-share-input"
      />
      <button
        id="copy-link-button"
        type="button"
        phx-hook="CopyText"
        data-copy-target="#game-share-link"
        class="play-button play-button-primary"
      >
        <.icon name="hero-link" class="size-4" />
        <span data-copy-label aria-live="polite">Copy link</span>
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :side, :atom, required: true
  attr :token, :any, required: true
  attr :current_token, :string, required: true
  attr :connected?, :boolean, required: true
  attr :current?, :boolean, required: true
  attr :count, :integer, required: true
  attr :winner?, :boolean, required: true

  def player_strip(assigns) do
    ~H"""
    <div
      id={"#{@side}-player"}
      class={["match-player", @current? && "match-player-current"]}
      data-to-move={to_string(@current?)}
    >
      <span
        class={["match-player-piece", @side == :black && "match-player-piece-black"]}
        aria-hidden="true"
      ><img src={~p"/images/pawn.svg"} width="32" height="32" alt="" /></span>
      <div class="min-w-0 flex-1">
        <p id={"#{@side}-seat-status"} class="text-sm font-semibold text-stone-100">
          {@label}: {seat_status(@token, @current_token, @connected?)}
        </p>
        <p class="mt-0.5 text-xs text-stone-400">
          {@count} {if @count == 1, do: "pawn", else: "pawns"}
        </p>
      </div>
      <span :if={@current?} class="match-turn-marker">To move</span>
      <span :if={@winner?} class="match-turn-marker"><.icon name="hero-trophy" class="size-4" />
      Winner</span>
      <span
        :if={!is_nil(@token)}
        class={["match-presence-dot", @connected? && "match-presence-connected"]}
        role="img"
        aria-label={if @connected?, do: "Connected", else: "Disconnected"}
      ></span>
    </div>
    """
  end

  attr :opponent_label, :string, required: true

  def resign_dialog(assigns) do
    ~H"""
    <div
      id="resign-dialog-overlay"
      phx-window-keydown="close-resign"
      phx-key="escape"
      phx-mounted={JS.focus(to: "#keep-playing-button")}
      phx-remove={JS.pop_focus()}
      class="match-dialog-overlay"
    >
      <div class="match-dialog-backdrop" aria-hidden="true"></div>
      <.focus_wrap
        id="resign-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="resign-dialog-title"
        aria-describedby="resign-dialog-description"
        class="match-dialog"
      >
        <h2 id="resign-dialog-title" class="display-copy text-3xl text-stone-100">
          Resign this game?
        </h2>
        <p id="resign-dialog-description" class="mt-3 text-sm leading-6 text-stone-300">
          {@opponent_label} will win. This ends the current game for both players.
        </p>
        <div class="mt-6 flex flex-wrap gap-3">
          <button
            id="keep-playing-button"
            type="button"
            phx-click="close-resign"
            class="play-button play-button-secondary"
          >Keep playing</button>
          <button
            id="confirm-resign-button"
            type="button"
            phx-click="resign-game"
            phx-disable-with="Resigning…"
            class="play-button match-resign-confirm"
          >Resign game</button>
        </div>
      </.focus_wrap>
    </div>
    """
  end

  defp seat_status(:ai, _current_token, _connected?), do: "AI"
  defp seat_status(nil, _current_token, _connected?), do: "Open"
  defp seat_status(token, token, _connected?), do: "You"
  defp seat_status(_token, _current_token, true), do: "Connected"
  defp seat_status(_token, _current_token, false), do: "Disconnected"
end
