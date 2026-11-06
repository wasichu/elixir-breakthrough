defmodule BreakthroughWeb.RulesComponents do
  use BreakthroughWeb, :html

  def rules_modal(assigns) do
    ~H"""
    <div
      id="rules-modal"
      phx-window-keydown="close-rules"
      phx-key="escape"
      phx-mounted={JS.focus(to: "#close-rules-button")}
      phx-remove={JS.pop_focus()}
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto px-3 py-3 sm:items-center sm:px-6 sm:py-6"
    >
      <button
        id="rules-modal-backdrop"
        type="button"
        phx-click="close-rules"
        class="absolute inset-0 bg-zinc-950/80 backdrop-blur-sm"
        aria-label="Close rules dialog"
      ></button>
      <.focus_wrap
        id="rules-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="rules-title"
        class="relative z-10 max-h-[calc(100dvh-1.5rem)] w-full max-w-4xl overflow-y-auto rounded-lg border border-white/12 bg-zinc-950/95 p-4 shadow-[0_30px_120px_rgba(0,0,0,0.5)] sm:max-h-[calc(100dvh-3rem)] sm:p-6 lg:p-8"
      >
        <div class="flex items-start justify-between gap-4 sm:gap-6">
          <div class="space-y-3">
            <h2 id="rules-title" class="display-copy text-2xl text-white sm:text-4xl">
              How Breakthrough Works
            </h2>
            <p class="max-w-xl text-sm leading-7 text-zinc-300 sm:text-base">
              White moves first. Move one pawn each turn, and win by reaching the far edge or capturing every opposing pawn.
            </p>
          </div>
          <button
            id="close-rules-button"
            type="button"
            phx-click="close-rules"
            class="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-white/10 bg-white/5 text-zinc-200 transition hover:bg-white/10 sm:h-11 sm:w-11"
            aria-label="Close rules"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="mt-5 grid gap-3 text-sm leading-6 text-zinc-300 sm:mt-8 sm:grid-cols-2 sm:leading-7 lg:grid-cols-4">
          <.rules_card
            title="Move"
            diagram_id="rules-move-diagram"
            squares={move_diagram()}
          >
            Pawns move one square straight or diagonally forward into an empty square.
          </.rules_card>
          <.rules_card
            title="Capture"
            diagram_id="rules-capture-diagram"
            squares={capture_diagram()}
          >
            Capture only by moving one square diagonally forward onto an opposing pawn.
          </.rules_card>
          <.rules_card
            title="Limits"
            diagram_id="rules-limits-diagram"
            squares={limits_diagram()}
          >
            Captures are optional, never chained, and a blocked pawn cannot move straight ahead.
          </.rules_card>
          <.rules_card title="Win" diagram_id="rules-win-diagram" squares={win_diagram()}>
            Reach the opposite back rank or leave the opponent with no pawns.
          </.rules_card>
        </div>
      </.focus_wrap>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :diagram_id, :string, required: true
  attr :squares, :list, required: true
  slot :inner_block, required: true

  defp rules_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-white/8 bg-white/5 p-4 sm:p-5">
      <p class="font-semibold text-white">{@title}</p>
      <.rules_diagram id={@diagram_id} squares={@squares} />
      <p class="mt-2">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :squares, :list, required: true

  defp rules_diagram(assigns) do
    ~H"""
    <div
      id={@id}
      class="mx-auto mt-3 grid aspect-square w-24 grid-cols-4 overflow-hidden rounded-lg border border-zinc-700 bg-zinc-900 sm:mt-4 sm:w-full"
      aria-hidden="true"
    >
      <div
        :for={square <- @squares}
        class={[
          "relative flex items-center justify-center border border-zinc-900/55",
          if(square.tone == :light, do: "bg-[#b99568]", else: "bg-[#5e4436]"),
          square.marker in [:finish, :white_finish] && "bg-emerald-300/35"
        ]}
      >
        <span
          :if={square.marker == :target}
          class="h-6 w-6 rounded-full border border-emerald-100/70 bg-emerald-300/45"
        ></span>
        <span
          :if={square.marker in [:blocked, :blocked_black]}
          class="absolute inset-2 rounded-md border border-rose-100/50 bg-rose-500/25"
        ></span>
        <span
          :if={square.marker == :chain}
          class="absolute inset-3 rounded-full border-2 border-rose-100/80"
        >
          <span class="absolute left-1/2 top-0 h-full w-0.5 -translate-x-1/2 rotate-45 bg-rose-100/80"></span>
        </span>
        <img
          :if={square.marker in [:white, :white_finish]}
          src={~p"/images/pawn.svg"}
          alt=""
          class="relative h-6 w-6 drop-shadow-[0_2px_2px_rgba(0,0,0,0.75)] sm:h-10 sm:w-10"
        />
        <img
          :if={square.marker in [:black, :blocked_black]}
          src={~p"/images/pawn.svg"}
          alt=""
          class="relative h-6 w-6 brightness-[0.28] contrast-[1.25] saturate-0 drop-shadow-[0_2px_1px_rgba(255,244,220,0.22)] sm:h-10 sm:w-10"
        />
      </div>
    </div>
    """
  end

  defp move_diagram do
    diagram_squares(fn
      {3, 2} -> :white
      {2, col} when col in [1, 2, 3] -> :target
      _coord -> nil
    end)
  end

  defp capture_diagram do
    diagram_squares(fn
      {3, 2} -> :white
      {2, col} when col in [1, 3] -> :black
      _coord -> nil
    end)
  end

  defp limits_diagram do
    diagram_squares(fn
      {4, 2} -> :white
      {3, 2} -> :blocked_black
      {3, 3} -> :black
      {2, 4} -> :chain
      _coord -> nil
    end)
  end

  defp win_diagram do
    diagram_squares(fn
      {1, 3} -> :white_finish
      {1, _col} -> :finish
      {3, 1} -> :black
      _coord -> nil
    end)
  end

  defp diagram_squares(marker_fun) do
    for row <- 1..4, col <- 1..4 do
      %{
        tone: if(rem(row + col, 2) == 0, do: :light, else: :dark),
        marker: marker_fun.({row, col})
      }
    end
  end
end
