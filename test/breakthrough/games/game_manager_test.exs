defmodule Breakthrough.Games.GameManagerTest do
  use ExUnit.Case, async: true

  alias Breakthrough.Games.GameManager

  test "players join as white, black, then spectator" do
    {:ok, game_id} = GameManager.create_game()

    assert {:ok, :white, state} = GameManager.join_game(game_id, "token-white")
    assert state.players.white == "token-white"
    assert state.players.black == nil
    assert state.player_presence == %{white: false, black: false}
    assert state.spectator_count == 0

    assert {:ok, :black, state} = GameManager.join_game(game_id, "token-black")
    assert state.players.white == "token-white"
    assert state.players.black == "token-black"
    assert state.player_presence == %{white: false, black: false}
    assert state.spectator_count == 0

    assert {:ok, :spectator, state} = GameManager.join_game(game_id, "token-spectator")
    assert state.players.white == "token-white"
    assert state.players.black == "token-black"
    assert state.spectator_count == 0
  end

  test "make_move/4 rejects spectators and wrong-turn players" do
    {:ok, game_id} = GameManager.create_game()
    {:ok, :white, _state} = GameManager.join_game(game_id, "token-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "token-black")

    assert {:error, :spectator} =
             GameManager.make_move(game_id, "token-spectator", {7, 4}, {6, 4})

    assert {:error, :not_your_turn} =
             GameManager.make_move(game_id, "token-black", {2, 4}, {3, 4})
  end

  test "resign/2 awards the game to the opponent" do
    {:ok, game_id} = GameManager.create_game()
    {:ok, :white, _state} = GameManager.join_game(game_id, "token-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "token-black")

    assert {:ok, state} = GameManager.resign(game_id, "token-white")
    assert state.game.winner == :black
    assert state.game.status == :finished
  end

  test "lobby snapshot tracks active and recent games" do
    game_id = "lobby-" <> Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, ^game_id} = GameManager.create_game(id: game_id)

    snapshot = GameManager.lobby_snapshot()
    assert snapshot.active_games_count >= 1
    assert game_id in snapshot.recent_games
  end

  test "started games expire after both connected players leave" do
    game_id = "expire-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, ^game_id} = GameManager.create_game(id: game_id, cleanup_timeout_ms: 20)
    {:ok, :white, _state} = GameManager.join_game(game_id, "token-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "token-black")

    white_pid = spawn(fn -> Process.sleep(:infinity) end)
    black_pid = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, state} = GameManager.track_connection(game_id, "token-white", white_pid)
    assert state.player_presence == %{white: true, black: false}

    assert {:ok, state} = GameManager.track_connection(game_id, "token-black", black_pid)
    assert state.player_presence == %{white: true, black: true}

    assert {:ok, _state} = GameManager.make_move(game_id, "token-white", {7, 1}, {6, 1})

    Process.exit(black_pid, :kill)

    assert_eventually(fn ->
      assert {:ok, state} = GameManager.get_state(game_id)
      assert state.player_presence == %{white: true, black: false}
    end)

    Process.exit(white_pid, :kill)

    assert_eventually(fn ->
      assert Registry.lookup(Breakthrough.Games.Registry, game_id) == []
      snapshot = GameManager.lobby_snapshot()
      refute game_id in snapshot.recent_games
    end)
  end

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(fun, 1), do: fun.()

  defp assert_eventually(fun, attempts) do
    try do
      fun.()
    rescue
      _error in [ExUnit.AssertionError] ->
        Process.sleep(10)
        assert_eventually(fun, attempts - 1)
    end
  end
end
