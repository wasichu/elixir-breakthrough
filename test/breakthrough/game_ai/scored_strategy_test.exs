defmodule Breakthrough.GameAI.ScoredStrategyTest do
  use ExUnit.Case, async: true

  alias Breakthrough.GameAI.ScoredStrategy

  test "prefers an immediate winning move" do
    game = %{
      board: %{
        {1, 8} => :white,
        {7, 1} => :black
      },
      current_player: :black,
      winner: nil,
      move_history: [],
      status: :in_progress
    }

    assert {:ok, %{from: {7, 1}, to: to}} = ScoredStrategy.choose_move(game, :black)
    assert to in [{8, 1}, {8, 2}]
  end

  test "prefers a capture over a non-capturing move" do
    game = %{
      board: %{
        {7, 8} => :white,
        {4, 4} => :white,
        {3, 3} => :black
      },
      current_player: :black,
      winner: nil,
      move_history: [],
      status: :in_progress
    }

    assert {:ok, %{from: {3, 3}, to: {4, 4}}} = ScoredStrategy.choose_move(game, :black)
  end

  test "prefers the move with the larger advancement bonus when other factors tie" do
    game = %{
      board: %{
        {1, 8} => :white,
        {4, 1} => :black,
        {5, 7} => :black,
        {5, 2} => :black,
        {6, 1} => :black,
        {6, 2} => :black,
        {6, 3} => :black,
        {6, 6} => :black,
        {6, 8} => :black,
        {7, 1} => :black,
        {7, 2} => :black,
        {7, 3} => :black,
        {7, 4} => :black,
        {7, 5} => :black,
        {7, 6} => :black,
        {7, 7} => :black,
        {7, 8} => :black,
        {8, 1} => :black,
        {8, 2} => :black,
        {8, 3} => :black,
        {8, 4} => :black,
        {8, 5} => :black,
        {8, 6} => :black,
        {8, 7} => :black,
        {8, 8} => :black
      },
      current_player: :black,
      winner: nil,
      move_history: [],
      status: :in_progress
    }

    assert {:ok, %{from: {5, 7}, to: {6, 7}}} = ScoredStrategy.choose_move(game, :black)
  end

  test "returns one of the best moves when scores tie" do
    game = %{
      board: %{
        {1, 8} => :white,
        {3, 1} => :black,
        {3, 4} => :black,
        {4, 3} => :black,
        {4, 5} => :black,
        {4, 2} => :black,
        {5, 1} => :black,
        {5, 2} => :black,
        {5, 3} => :black,
        {5, 4} => :black,
        {5, 5} => :black,
        {5, 6} => :black,
        {5, 7} => :black,
        {5, 8} => :black,
        {6, 1} => :black,
        {6, 2} => :black,
        {6, 3} => :black,
        {6, 4} => :black,
        {6, 5} => :black,
        {6, 6} => :black,
        {6, 7} => :black,
        {6, 8} => :black,
        {7, 1} => :black,
        {7, 2} => :black,
        {7, 3} => :black,
        {7, 4} => :black,
        {7, 5} => :black,
        {7, 6} => :black,
        {7, 7} => :black,
        {7, 8} => :black,
        {8, 1} => :black,
        {8, 2} => :black,
        {8, 3} => :black,
        {8, 4} => :black,
        {8, 5} => :black,
        {8, 6} => :black,
        {8, 7} => :black,
        {8, 8} => :black
      },
      current_player: :black,
      winner: nil,
      move_history: [],
      status: :in_progress
    }

    assert {:ok, move} = ScoredStrategy.choose_move(game, :black)
    assert move in [%{from: {3, 1}, to: {4, 1}}, %{from: {3, 4}, to: {4, 4}}]
  end
end
