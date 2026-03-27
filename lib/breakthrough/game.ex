defmodule Breakthrough.Game do
  @moduledoc """
  Pure domain logic for a Breakthrough game.
  """

  @board_size 8
  @players [:white, :black]

  @type player :: :white | :black
  @type coord :: {1..8, 1..8}
  @type piece :: player()
  @type move :: %{from: coord(), to: coord(), player: player(), capture?: boolean()}

  @type t :: %{
          board: %{optional(coord()) => piece()},
          current_player: player(),
          winner: player() | nil,
          move_history: [move()],
          status: :not_started | :in_progress | :finished,
          finish_reason: nil | {:resignation, player()}
        }

  @spec new() :: t()
  def new do
    %{
      board: starting_board(),
      current_player: :white,
      winner: nil,
      move_history: [],
      status: :not_started,
      finish_reason: nil
    }
  end

  @spec board_size() :: pos_integer()
  def board_size, do: @board_size

  @spec players() :: [player()]
  def players, do: @players

  @spec piece_at(t(), coord()) :: piece() | nil
  def piece_at(game, coord), do: Map.get(game.board, coord)

  @spec legal_moves(t(), coord()) :: [coord()]
  def legal_moves(game, from) do
    case piece_at(game, from) do
      player when player == game.current_player and is_nil(game.winner) ->
        do_legal_moves(game, from)

      _ ->
        []
    end
  end

  @spec available_moves(t(), player()) :: [%{from: coord(), to: coord()}]
  def available_moves(game, player) do
    if game.winner || game.current_player != player do
      []
    else
      game.board
      |> Enum.reduce([], fn
        {from, ^player}, moves ->
          legal_moves(game, from)
          |> Enum.map(&%{from: from, to: &1})
          |> Kernel.++(moves)

        _, moves ->
          moves
      end)
      |> Enum.reverse()
    end
  end

  @spec move(t(), coord(), coord()) :: {:ok, t()} | {:error, :invalid_move | :game_over}
  def move(%{winner: winner}, _from, _to) when winner in [:white, :black],
    do: {:error, :game_over}

  def move(game, from, to) do
    if to in legal_moves(game, from) do
      capture? = capture_move?(game, from, to)
      board = apply_move(game, from, to)
      winner = winning_player(game.current_player, board, to)

      updated_game =
        game
        |> Map.put(:board, board)
        |> Map.put(:current_player, next_player(game.current_player, winner))
        |> Map.put(:winner, winner)
        |> Map.put(
          :move_history,
          game.move_history ++
            [%{from: from, to: to, player: game.current_player, capture?: capture?}]
        )
        |> Map.put(:status, game_status(winner))
        |> Map.put(:finish_reason, nil)

      {:ok, updated_game}
    else
      {:error, :invalid_move}
    end
  end

  @spec resign(t(), player()) :: {:ok, t()} | {:error, :game_over}
  def resign(%{winner: winner}, _player) when winner in [:white, :black],
    do: {:error, :game_over}

  def resign(game, player) do
    {:ok,
     game
     |> Map.put(:winner, opponent(player))
     |> Map.put(:status, :finished)
     |> Map.put(:finish_reason, {:resignation, player})}
  end

  defp do_legal_moves(game, {row, col}) do
    delta = if game.current_player == :white, do: -1, else: 1
    next_row = row + delta

    [
      {next_row, col},
      {next_row, col - 1},
      {next_row, col + 1}
    ]
    |> Enum.filter(&valid_move(game, {row, col}, &1))
  end

  defp valid_move(game, {_from_row, from_col}, {to_row, to_col}) do
    valid_coord(to_row, to_col) and
      case piece_at(game, {to_row, to_col}) do
        occupant when to_col == from_col ->
          is_nil(occupant)

        occupant ->
          occupant != game.current_player
      end
  end

  defp capture_move?(_game, {_from_row, from_col}, {_to_row, to_col}) when to_col == from_col,
    do: false

  defp capture_move?(game, _from, to) do
    piece_at(game, to) == opponent(game.current_player)
  end

  defp apply_move(game, from, to) do
    game.board
    |> Map.delete(from)
    |> Map.put(to, game.current_player)
  end

  defp winning_player(player, board, {row, _col}) do
    cond do
      player == :white and row == 1 ->
        :white

      player == :black and row == @board_size ->
        :black

      Enum.any?(board, fn {_coord, occupant} -> occupant == opponent(player) end) ->
        nil

      true ->
        player
    end
  end

  defp game_status(nil), do: :in_progress
  defp game_status(_winner), do: :finished

  defp next_player(current_player, nil), do: opponent(current_player)
  defp next_player(current_player, _winner), do: current_player

  defp opponent(:white), do: :black
  defp opponent(:black), do: :white

  defp valid_coord(row, col) do
    row >= 1 and row <= @board_size and col >= 1 and col <= @board_size
  end

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
