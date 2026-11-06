defmodule Breakthrough.Games.GameManagerTest do
  use ExUnit.Case, async: true

  alias Breakthrough.Games.GameManager

  test "an unclaimed invitation expires and releases its creator slot" do
    token = creator_token()
    assert {:ok, id} = GameManager.create_game(creator_token: token, waiting_timeout_ms: 50)
    [{pid, _}] = Registry.lookup(Breakthrough.Games.Registry, id)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    assert {:error, :not_found} = GameManager.get_state(id)
    assert {:error, :not_found} = GameManager.get_created_game(token)
    assert {:ok, _new_id} = GameManager.create_game(creator_token: token)
  end

  test "AI games expire when the human never makes a first move" do
    assert {:ok, id} =
             GameManager.create_game(
               mode: :vs_ai,
               creator_token: creator_token(),
               ready_timeout_ms: 50
             )

    [{pid, _}] = Registry.lookup(Breakthrough.Games.Registry, id)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    assert {:error, :not_found} = GameManager.get_state(id)
  end

  test "resigning before any move still expires the finished game" do
    token = creator_token()

    assert {:ok, id} =
             GameManager.create_game(mode: :vs_ai, creator_token: token, finished_timeout_ms: 50)

    [{pid, _}] = Registry.lookup(Breakthrough.Games.Registry, id)
    ref = Process.monitor(pid)
    assert {:ok, state} = GameManager.resign(id, token)
    assert state.game.move_history == []
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    assert {:error, :not_found} = GameManager.get_state(id)
  end

  test "joining and subsequent moves ignore expiry messages from cancelled deadlines" do
    white = creator_token()
    black = creator_token()
    assert {:ok, id} = GameManager.create_game(creator_token: white)
    [{pid, _}] = Registry.lookup(Breakthrough.Games.Registry, id)
    waiting_ref = :sys.get_state(pid).waiting_timer_ref
    assert {:ok, :black, _state} = GameManager.join_game(id, black)
    send(pid, {:timeout, waiting_ref, :expire_if_waiting})
    assert {:ok, _state} = GameManager.make_move(id, white, {7, 1}, {6, 1})
    move_ref = :sys.get_state(pid).move_timer_ref
    assert {:ok, _state} = GameManager.make_move(id, black, {2, 1}, {3, 1})
    send(pid, {:timeout, move_ref, :expire_if_stalled})
    assert {:ok, state} = GameManager.get_state(id)
    assert length(state.game.move_history) == 2
  end

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

  test "a waiting player cannot bypass the lobby by submitting a move directly" do
    token = creator_token()
    assert {:ok, id} = GameManager.create_game(creator_token: token)
    assert {:error, :not_ready} = GameManager.make_move(id, token, {7, 1}, {6, 1})
    assert {:ok, state} = GameManager.get_state(id)
    assert state.game.status == :not_started
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

  test "games expire after no move activity for the configured timeout" do
    game_id = "expire-stalled-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, ^game_id} =
      GameManager.create_game(id: game_id, move_timeout_ms: 20)

    {:ok, :white, _state} = GameManager.join_game(game_id, "stalled-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "stalled-black")
    assert {:ok, _state} = GameManager.make_move(game_id, "stalled-white", {7, 1}, {6, 1})

    assert_eventually(fn ->
      assert Registry.lookup(Breakthrough.Games.Registry, game_id) == []
      snapshot = GameManager.lobby_snapshot()
      refute Enum.any?(snapshot.recent_games, &(&1.id == game_id))
    end)
  end

  test "a new move resets the move inactivity timeout" do
    game_id = "expire-stalled-reset-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, ^game_id} =
      GameManager.create_game(id: game_id, move_timeout_ms: 30)

    {:ok, :white, _state} = GameManager.join_game(game_id, "stalled-reset-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "stalled-reset-black")
    assert {:ok, _state} = GameManager.make_move(game_id, "stalled-reset-white", {7, 1}, {6, 1})

    Process.sleep(15)
    assert {:ok, _state} = GameManager.make_move(game_id, "stalled-reset-black", {2, 1}, {3, 1})
    Process.sleep(20)

    assert {:ok, state} = GameManager.get_state(game_id)
    assert length(state.game.move_history) == 2
  end

  test "finished games also expire after the inactivity timeout" do
    game_id = "expire-finished-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, ^game_id} =
      GameManager.create_game(id: game_id, move_timeout_ms: 200, finished_timeout_ms: 20)

    {:ok, :white, _state} = GameManager.join_game(game_id, "finished-white")
    {:ok, :black, _state} = GameManager.join_game(game_id, "finished-black")
    assert {:ok, _state} = GameManager.make_move(game_id, "finished-white", {7, 1}, {6, 1})
    assert {:ok, _state} = GameManager.resign(game_id, "finished-black")

    assert_eventually(fn ->
      assert Registry.lookup(Breakthrough.Games.Registry, game_id) == []
      snapshot = GameManager.lobby_snapshot()
      refute Enum.any?(snapshot.recent_games, &(&1.id == game_id))
    end)
  end

  test "a creator can have only one unfinished game across modes" do
    token = creator_token()
    assert {:ok, game_id} = GameManager.create_game(creator_token: token)
    assert {:ok, state} = GameManager.get_state(game_id)
    assert state.players.white == token

    for mode <- [:pvp, :vs_ai] do
      assert {:error, {:active_game, ^game_id}} =
               GameManager.create_game(creator_token: token, mode: mode)
    end

    assert {:ok, _other_game} = GameManager.create_game(creator_token: creator_token())
  end

  test "creation claims the white seat before another visitor joins" do
    token = creator_token()
    assert {:ok, game_id} = GameManager.create_game(creator_token: token)
    assert {:ok, :black, state} = GameManager.join_game(game_id, creator_token())
    assert state.players.white == token
    assert {:ok, :white, _state} = GameManager.join_game(game_id, token)
  end

  test "concurrent requests reserve exactly one game for a creator" do
    token = creator_token()

    results =
      1..12
      |> Task.async_stream(fn _ -> GameManager.create_game(creator_token: token) end,
        max_concurrency: 12
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, game_id}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &(&1 == {:error, {:active_game, game_id}})) == 11
  end

  test "finishing a game releases the creator's slot while its result remains available" do
    token = creator_token()
    assert {:ok, game_id} = GameManager.create_game(creator_token: token, mode: :vs_ai)
    assert {:ok, _state} = GameManager.resign(game_id, token)
    assert {:ok, next_id} = GameManager.create_game(creator_token: token)
    refute next_id == game_id
    assert {:ok, %{game: %{status: :finished}}} = GameManager.get_state(game_id)
  end

  test "winning by reaching the back rank releases the creator's slot" do
    white = creator_token()
    black = creator_token()
    {:ok, game_id} = GameManager.create_game(creator_token: white)
    {:ok, :black, _state} = GameManager.join_game(game_id, black)

    for {player, from, to} <- [
          {white, {7, 1}, {6, 1}},
          {black, {2, 8}, {3, 8}},
          {white, {6, 1}, {5, 1}},
          {black, {3, 8}, {4, 8}},
          {white, {5, 1}, {4, 1}},
          {black, {4, 8}, {5, 8}},
          {white, {4, 1}, {3, 1}},
          {black, {5, 8}, {6, 8}},
          {white, {3, 1}, {2, 2}},
          {black, {6, 8}, {7, 7}}
        ] do
      assert {:ok, _state} = GameManager.make_move(game_id, player, from, to)
    end

    assert {:ok, %{game: %{status: :finished, winner: :white}}} =
             GameManager.make_move(game_id, white, {2, 2}, {1, 1})

    assert {:ok, _next_id} = GameManager.create_game(creator_token: white)
  end

  test "expiration releases the creator's slot" do
    token = creator_token()

    assert {:ok, game_id} =
             GameManager.create_game(creator_token: token, ready_timeout_ms: 10)

    {:ok, :black, _state} = GameManager.join_game(game_id, creator_token())
    [{pid, _}] = Registry.lookup(Breakthrough.Games.Registry, game_id)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    assert {:ok, _next_id} = GameManager.create_game(creator_token: token)
  end

  test "a terminated game releases the creator's slot" do
    token = creator_token()
    assert {:ok, game_id} = GameManager.create_game(creator_token: token)
    [{pid, _}] = Registry.lookup(Breakthrough.Games.Registry, game_id)
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(Breakthrough.Games.GameSupervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1_000
    assert {:ok, _next_id} = GameManager.create_game(creator_token: token)
  end

  test "repeated rematch requests cannot create multiple active games" do
    token = creator_token()
    assert {:ok, game_id} = GameManager.create_game(creator_token: token, mode: :vs_ai)
    assert {:ok, _state} = GameManager.resign(game_id, token)
    assert {:ok, rematch_id} = GameManager.create_rematch(game_id, token)
    assert {:error, {:active_game, ^rematch_id}} = GameManager.create_rematch(game_id, token)
    assert {:error, {:active_game, ^rematch_id}} = GameManager.create_game(creator_token: token)
  end

  test "only the waiting game's white player can cancel, freeing the creation slot" do
    token = creator_token()
    assert {:ok, game_id} = GameManager.create_game(creator_token: token)
    assert {:error, :not_waiting} = GameManager.cancel_game(game_id, creator_token())
    assert :ok = GameManager.cancel_game(game_id, token)
    assert {:ok, _next_id} = GameManager.create_game(creator_token: token)
  end

  test "a waiting game cannot be cancelled after an opponent joins" do
    token = creator_token()
    assert {:ok, game_id} = GameManager.create_game(creator_token: token)
    assert {:ok, :black, _state} = GameManager.join_game(game_id, creator_token())
    assert {:error, :not_waiting} = GameManager.cancel_game(game_id, token)
    assert {:ok, _state} = GameManager.make_move(game_id, token, {7, 1}, {6, 1})
    assert {:error, {:active_game, ^game_id}} = GameManager.create_game(creator_token: token)
  end

  defp creator_token, do: "creator-#{System.unique_integer([:positive])}"

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
