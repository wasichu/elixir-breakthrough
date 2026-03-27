defmodule Breakthrough.Game do
  @moduledoc """
  Minimal game-state container for the v1 Breakthrough UI.

  The rendering layer can depend on this module now, while the actual move
  rules can be filled in later without replacing the homepage structure.
  """

  @board_size 8
  @players [:white, :black]

  @type player :: :white | :black
  @type coord :: {1..8, 1..8}
  @type piece :: player()

  @type t :: %{
          board: %{optional(coord()) => piece()},
          current_turn: player(),
          selected_square: coord() | nil,
          winner: player() | nil,
          status: :not_started | :in_progress | :finished,
          last_move: {coord(), coord()} | nil
        }

  @spec new() :: t()
  def new do
    %{
      board: starting_board(),
      current_turn: :white,
      selected_square: nil,
      winner: nil,
      status: :not_started,
      last_move: nil
    }
  end

  @spec board_size() :: pos_integer()
  def board_size, do: @board_size

  @spec players() :: [player()]
  def players, do: @players

  @spec piece_at(t(), coord()) :: piece() | nil
  def piece_at(game, coord), do: Map.get(game.board, coord)

  defp own_piece_at(game, coord) do
    piece_at(game, coord) == game.current_turn
  end

  @spec select_square(t(), coord()) :: {:ok, t()} | {:error, :invalid_selection}
  def select_square(game, coord) do
    case piece_at(game, coord) do
      player when player == game.current_turn ->
        {:ok, %{game | selected_square: coord}}

      _ ->
        {:error, :invalid_selection}
    end
  end

  @spec clear_selection(t()) :: t()
  def clear_selection(game), do: %{game | selected_square: nil}

  @spec legal_moves(t(), coord()) :: [coord()]
  def legal_moves(game, coord) do
    if own_piece_at(game, coord) do
      do_legal_moves(game, coord)
    else
      []
    end
  end

  defp do_legal_moves(game, {x, y}) do
    white_to_move = game.current_turn == :white
    new_row = if white_to_move, do: x - 1, else: x + 1

    possible_moves = [
      {new_row, y},
      {new_row, y - 1},
      {new_row, y + 1}
    ]

    Enum.filter(possible_moves, fn move -> valid_move(game, move) end)
  end

  defp valid_move(game, coord = {x, y}) do
    valid_coord(x, y) and not own_piece_at(game, coord)
  end

  defp valid_coord(x, y) do
    x >= 1 and x <= @board_size and y >= 1 and y <= @board_size
  end

  @spec move(t(), coord(), coord()) :: {:ok, t()} | {:error, :not_implemented}
  def move(game, from, to) when from == to, do: {:ok, clear_selection(game)}

  def move(game, from, to) do
    if to in legal_moves(game, from) do
      winner = winning_player(game, to)
      status = if not is_nil(winner), do: :finished, else: :in_progress

      {:ok,
       %{
         game
         | current_turn: next_turn(game),
           board: apply_move(game, from, to),
           winner: winner,
           status: status,
           last_move: {from, to},
           selected_square: nil
       }}
    else
      {:ok, clear_selection(game)}
    end
  end

  defp apply_move(game, from, to) do
    game.board
    |> Map.delete(from)
    |> Map.put(to, game.current_turn)
  end

  @spec winning_player(t(), coord()) :: player() | nil
  defp winning_player(game, {row, _col}) do
    case {game.current_turn, row} do
      {:white, 1} ->
        :white

      {:black, @board_size} ->
        :black

      _ ->
        nil
    end
  end

  defp next_turn(%{current_turn: :white}), do: :black
  defp next_turn(_game), do: :white

  defp starting_board do
    white_pawns =
      for row <- [7, 8],
          col <- 1..@board_size,
          into: %{} do
        {{row, col}, :white}
      end

    black_pawns =
      for row <- [1, 2],
          col <- 1..@board_size,
          into: %{} do
        {{row, col}, :black}
      end

    Map.merge(white_pawns, black_pawns)
  end
end
