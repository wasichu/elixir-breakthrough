defmodule Breakthrough.GameTest do
  use ExUnit.Case, async: true

  alias Breakthrough.Game

  test "new/0 initializes the starting board and metadata" do
    game = Game.new()

    assert game.current_turn == :white
    assert game.selected_square == nil
    assert game.winner == nil
    assert game.status == :not_started
    assert game.last_move == nil

    assert Game.piece_at(game, {1, 1}) == :black
    assert Game.piece_at(game, {2, 8}) == :black
    assert Game.piece_at(game, {7, 1}) == :white
    assert Game.piece_at(game, {8, 8}) == :white
    assert Game.piece_at(game, {4, 4}) == nil
  end

  test "select_square/2 accepts current turn pieces and rejects others" do
    game = Game.new()

    assert {:ok, selected_game} = Game.select_square(game, {7, 3})
    assert selected_game.selected_square == {7, 3}

    assert {:error, :invalid_selection} = Game.select_square(game, {2, 3})
    assert {:error, :invalid_selection} = Game.select_square(game, {4, 4})
  end

  test "legal_moves/2 returns forward and diagonal moves for a movable piece" do
    game = Game.new()

    assert Game.legal_moves(game, {7, 4}) == [{6, 4}, {6, 3}, {6, 5}]
    assert Game.legal_moves(game, {7, 1}) == [{6, 1}, {6, 2}]
    assert Game.legal_moves(game, {2, 4}) == []
    assert Game.legal_moves(game, {4, 4}) == []
  end

  test "move/3 applies a legal move and advances the game" do
    game = Game.new()

    assert {:ok, moved_game} = Game.move(game, {7, 4}, {6, 4})

    assert Game.piece_at(moved_game, {7, 4}) == nil
    assert Game.piece_at(moved_game, {6, 4}) == :white
    assert moved_game.current_turn == :black
    assert moved_game.status == :in_progress
    assert moved_game.winner == nil
    assert moved_game.last_move == {{7, 4}, {6, 4}}
    assert moved_game.selected_square == nil
  end

  test "move/3 marks a winning move as finished" do
    game = %{
      board: %{{2, 4} => :white},
      current_turn: :white,
      selected_square: {2, 4},
      winner: nil,
      status: :in_progress,
      last_move: nil
    }

    assert {:ok, moved_game} = Game.move(game, {2, 4}, {1, 4})

    assert Game.piece_at(moved_game, {1, 4}) == :white
    assert moved_game.winner == :white
    assert moved_game.status == :finished
    assert moved_game.last_move == {{2, 4}, {1, 4}}
  end
end
