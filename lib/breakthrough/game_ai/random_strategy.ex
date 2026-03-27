defmodule Breakthrough.GameAI.RandomStrategy do
  @moduledoc false
  @behaviour Breakthrough.GameAI

  alias Breakthrough.Game

  @impl true
  def choose_move(game, player) do
    case Game.available_moves(game, player) do
      [] -> {:error, :no_legal_moves}
      moves -> {:ok, Enum.random(moves)}
    end
  end
end
