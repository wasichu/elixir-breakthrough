defmodule Breakthrough.GameTest do
  use ExUnit.Case, async: true

  alias Breakthrough.Game

  test "new/0 initializes the starting board and metadata" do
    game = Game.new()

    assert game.current_player == :white
    assert game.winner == nil
    assert game.status == :not_started
    assert game.move_history == []

    assert Game.piece_at(game, {1, 1}) == :black
    assert Game.piece_at(game, {2, 8}) == :black
    assert Game.piece_at(game, {7, 1}) == :white
    assert Game.piece_at(game, {8, 8}) == :white
    assert Game.piece_at(game, {4, 4}) == nil
  end

  test "legal_moves/2 rejects non-current-player and empty squares" do
    game = Game.new()

    assert Game.legal_moves(game, {2, 3}) == []
    assert Game.legal_moves(game, {4, 4}) == []
  end

  test "legal_moves/2 returns forward and diagonal moves for a movable piece" do
    game = Game.new()

    assert Game.legal_moves(game, {7, 4}) == [{6, 4}, {6, 3}, {6, 5}]
    assert Game.legal_moves(game, {7, 1}) == [{6, 1}, {6, 2}]
  end

  test "move/3 applies a legal move and advances the game" do
    game = Game.new()

    assert {:ok, moved_game} = Game.move(game, {7, 4}, {6, 4})

    assert Game.piece_at(moved_game, {7, 4}) == nil
    assert Game.piece_at(moved_game, {6, 4}) == :white
    assert moved_game.current_player == :black
    assert moved_game.status == :in_progress
    assert moved_game.winner == nil

    assert moved_game.move_history == [
             %{from: {7, 4}, to: {6, 4}, player: :white, capture?: false}
           ]
  end

  test "move/3 marks a winning move as finished" do
    game = %{
      board: %{{2, 4} => :white},
      current_player: :white,
      winner: nil,
      move_history: [],
      status: :in_progress
    }

    assert {:ok, moved_game} = Game.move(game, {2, 4}, {1, 4})

    assert Game.piece_at(moved_game, {1, 4}) == :white
    assert moved_game.winner == :white
    assert moved_game.status == :finished
    assert moved_game.current_player == :white

    assert moved_game.move_history == [
             %{from: {2, 4}, to: {1, 4}, player: :white, capture?: false}
           ]
  end
end
