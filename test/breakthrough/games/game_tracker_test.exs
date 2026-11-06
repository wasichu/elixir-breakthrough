defmodule Breakthrough.Games.GameTrackerTest do
  # The recent-game list is global and capped, so concurrent creation changes it.
  use ExUnit.Case, async: false
  alias Breakthrough.Games.GameManager

  test "lobby snapshot tracks active and recent games" do
    game_id = "lobby-" <> Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, ^game_id} = GameManager.create_game(id: game_id)

    snapshot = GameManager.lobby_snapshot()
    assert snapshot.active_games_count >= 1
    assert Enum.any?(snapshot.recent_games, &(&1.id == game_id))
  end

  test "externally stopped processes disappear from the lobby" do
    assert {:ok, id} = GameManager.create_game()
    assert Enum.any?(GameManager.lobby_snapshot().recent_games, &(&1.id == id))
    [{pid, _}] = Registry.lookup(Breakthrough.Games.Registry, id)
    assert :ok = DynamicSupervisor.terminate_child(Breakthrough.Games.GameSupervisor, pid)

    assert_eventually(fn ->
      not Enum.any?(GameManager.lobby_snapshot().recent_games, &(&1.id == id))
    end)
  end

  test "late tracking messages cannot resurrect stopped games" do
    id = "stopped-#{System.unique_integer([:positive])}"
    Breakthrough.Games.GameTracker.track_game_started(id)
    refute Enum.any?(GameManager.lobby_snapshot().recent_games, &(&1.id == id))
  end

  test "finished games remain viewable but no longer count as active" do
    before = GameManager.lobby_snapshot().active_games_count
    token = "tracker-#{System.unique_integer([:positive])}"
    assert {:ok, id} = GameManager.create_game(mode: :vs_ai, creator_token: token)
    assert GameManager.lobby_snapshot().active_games_count == before + 1
    assert {:ok, _state} = GameManager.resign(id, token)
    snapshot = GameManager.lobby_snapshot()
    assert snapshot.active_games_count == before
    assert Enum.any?(snapshot.recent_games, &(&1.id == id && &1.status == :finished))
  end

  defp assert_eventually(fun, attempts \\ 50)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      receive do
      after
        10 -> assert_eventually(fun, attempts - 1)
      end
    end
  end
end
