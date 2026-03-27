defmodule Breakthrough.GameAI.ScoredStrategy do
  @moduledoc false
  @behaviour Breakthrough.GameAI

  alias Breakthrough.Game

  @win_bonus 100
  @capture_bonus 20

  @impl true
  def choose_move(game, player) do
    case Game.available_moves(game, player) do
      [] ->
        {:error, :no_legal_moves}

      moves ->
        moves
        |> Enum.map(&score_move(game, player, &1))
        |> best_moves()
        |> Enum.random()
        |> then(&{:ok, &1})
    end
  end

  defp score_move(game, player, %{from: from, to: to} = move) do
    {:ok, next_game} = Game.move(game, from, to)

    {move,
     win_bonus(next_game, player) +
       capture_bonus(game, player, to) +
       advancement_bonus(player, to)}
  end

  defp best_moves(scored_moves) do
    max_score =
      scored_moves
      |> Enum.map(&elem(&1, 1))
      |> Enum.max()

    scored_moves
    |> Enum.filter(&(elem(&1, 1) == max_score))
    |> Enum.map(&elem(&1, 0))
  end

  defp win_bonus(%{winner: player}, player), do: @win_bonus
  defp win_bonus(_game, _player), do: 0

  defp capture_bonus(game, player, to) do
    case Game.piece_at(game, to) do
      occupant when occupant in [:white, :black] and occupant != player -> @capture_bonus
      _ -> 0
    end
  end

  defp advancement_bonus(:black, {to_row, _col}), do: to_row - 1
  defp advancement_bonus(:white, {to_row, _col}), do: Game.board_size() - to_row
end
