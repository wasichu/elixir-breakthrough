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

  test "vs_ai games reserve black for the ai and apply the ai move after white moves" do
    game_id = "ai-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, ^game_id} =
      GameManager.create_game(
        id: game_id,
        mode: :vs_ai,
        ai_strategy: Breakthrough.TestSupport.FixedAIStrategy
      )

    assert {:ok, :white, state} = GameManager.join_game(game_id, "token-white")
    assert state.players.black == :ai

    assert {:ok, state} = GameManager.make_move(game_id, "token-white", {7, 1}, {6, 1})
    assert state.game.current_player == :white

    assert state.game.move_history == [
             %{from: {7, 1}, to: {6, 1}, player: :white, capture?: false},
             %{from: {2, 1}, to: {3, 1}, player: :black, capture?: false}
           ]
  end

  test "vs_ai create_rematch/1 creates a fresh game with the same mode" do
    game_id = "rematch-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, ^game_id} = GameManager.create_game(id: game_id, mode: :vs_ai)
    {:ok, :white, _state} = GameManager.join_game(game_id, "token-white")

    assert {:ok, state} = GameManager.resign(game_id, "token-white")
    assert state.game.status == :finished

    assert {:ok, rematch_id} = GameManager.create_rematch(game_id, "token-white")
    refute rematch_id == game_id

    assert {:ok, rematch_state} = GameManager.get_state(rematch_id)
    assert rematch_state.mode == :vs_ai
    assert rematch_state.game.status == :not_started
    assert rematch_state.players.white == "token-white"
    assert rematch_state.players.black == :ai
  end

  test "pvp rematch waits for both players and swaps colors in the new game" do
    game_id = "rematch-pvp-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, ^game_id} = GameManager.create_game(id: game_id)
    {:ok, :white, _state} = GameManager.join_game(game_id, "token-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "token-black")
    assert {:ok, _state} = GameManager.resign(game_id, "token-white")

    assert {:pending, state} = GameManager.create_rematch(game_id, "token-white")
    assert MapSet.equal?(state.rematch_votes, MapSet.new([:white]))

    assert {:ok, rematch_id} = GameManager.create_rematch(game_id, "token-black")
    refute rematch_id == game_id

    assert {:ok, rematch_state} = GameManager.get_state(rematch_id)
    assert rematch_state.mode == :pvp
    assert rematch_state.players.white == "token-black"
    assert rematch_state.players.black == "token-white"
    assert rematch_state.game.status == :not_started
  end

  test "spectators cannot create a rematch" do
    game_id = "rematch-spectator-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, ^game_id} = GameManager.create_game(id: game_id)
    {:ok, :white, _state} = GameManager.join_game(game_id, "token-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "token-black")
    {:ok, :spectator, _state} = GameManager.join_game(game_id, "token-spectator")
    assert {:ok, _state} = GameManager.resign(game_id, "token-white")

    assert {:error, :spectator} = GameManager.create_rematch(game_id, "token-spectator")
  end

  test "lobby snapshot tracks active and recent games" do
    game_id = "lobby-" <> Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, ^game_id} = GameManager.create_game(id: game_id)

    snapshot = GameManager.lobby_snapshot()
    assert snapshot.active_games_count >= 1
    assert Enum.any?(snapshot.recent_games, &(&1.id == game_id))
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

  test "unstarted pvp games expire a minute after the second player joins" do
    game_id = "expire-unstarted-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, ^game_id} =
      GameManager.create_game(id: game_id, cleanup_timeout_ms: 20, ready_timeout_ms: 20)

    {:ok, :white, _state} = GameManager.join_game(game_id, "unstarted-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "unstarted-black")

    assert_eventually(fn ->
      assert Registry.lookup(Breakthrough.Games.Registry, game_id) == []
      snapshot = GameManager.lobby_snapshot()
      refute Enum.any?(snapshot.recent_games, &(&1.id == game_id))
    end)
  end

  test "the first move cancels the unstarted pvp expiry timer" do
    game_id = "expire-unstarted-cancel-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, ^game_id} =
      GameManager.create_game(id: game_id, cleanup_timeout_ms: 20, ready_timeout_ms: 20)

    {:ok, :white, _state} = GameManager.join_game(game_id, "unstarted-cancel-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "unstarted-cancel-black")

    assert {:ok, _state} =
             GameManager.make_move(game_id, "unstarted-cancel-white", {7, 1}, {6, 1})

    Process.sleep(40)

    assert {:ok, state} = GameManager.get_state(game_id)

    assert state.game.move_history == [
             %{from: {7, 1}, to: {6, 1}, player: :white, capture?: false}
           ]
  end

  test "started pvp games do not expire when only one player leaves" do
    game_id = "expire-one-left-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, ^game_id} = GameManager.create_game(id: game_id, cleanup_timeout_ms: 20)
    {:ok, :white, _state} = GameManager.join_game(game_id, "one-left-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "one-left-black")

    white_pid = spawn(fn -> Process.sleep(:infinity) end)
    black_pid = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, _state} = GameManager.track_connection(game_id, "one-left-white", white_pid)
    assert {:ok, _state} = GameManager.track_connection(game_id, "one-left-black", black_pid)
    assert {:ok, _state} = GameManager.make_move(game_id, "one-left-white", {7, 1}, {6, 1})

    Process.exit(black_pid, :kill)
    Process.sleep(40)

    assert {:ok, state} = GameManager.get_state(game_id)
    assert state.player_presence == %{white: true, black: false}
  end

  test "vs ai games expire after the human player disconnects" do
    game_id = "expire-ai-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, ^game_id} = GameManager.create_game(id: game_id, mode: :vs_ai, cleanup_timeout_ms: 20)
    {:ok, :white, _state} = GameManager.join_game(game_id, "ai-white")

    white_pid = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, state} = GameManager.track_connection(game_id, "ai-white", white_pid)
    assert state.player_presence == %{white: true, black: true}

    Process.exit(white_pid, :kill)

    assert_eventually(fn ->
      assert Registry.lookup(Breakthrough.Games.Registry, game_id) == []
      snapshot = GameManager.lobby_snapshot()
      refute Enum.any?(snapshot.recent_games, &(&1.id == game_id))
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
