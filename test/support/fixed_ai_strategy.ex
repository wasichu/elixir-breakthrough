defmodule Breakthrough.TestSupport.FixedAIStrategy do
  @behaviour Breakthrough.GameAI

  @impl true
  def choose_move(_game, _player) do
    {:ok, %{from: {2, 1}, to: {3, 1}}}
  end
end
