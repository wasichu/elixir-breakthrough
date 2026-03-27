defmodule Breakthrough.Games.GameTracker do
  @moduledoc false
  use GenServer

  @topic "games:lobby"
  @recent_limit 5

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def track_game_started(game_id), do: GenServer.cast(__MODULE__, {:track_game_started, game_id})
  def track_game_stopped(game_id), do: GenServer.cast(__MODULE__, {:track_game_stopped, game_id})
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def topic, do: @topic

  @impl true
  def init(:ok) do
    {:ok, %{active_games: MapSet.new(), recent_games: []}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot(state), state}
  end

  @impl true
  def handle_cast({:track_game_started, game_id}, state) do
    next_state = %{
      active_games: MapSet.put(state.active_games, game_id),
      recent_games:
        [game_id | Enum.reject(state.recent_games, &(&1 == game_id))] |> Enum.take(@recent_limit)
    }

    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:track_game_stopped, game_id}, state) do
    next_state = %{
      active_games: MapSet.delete(state.active_games, game_id),
      recent_games: Enum.reject(state.recent_games, &(&1 == game_id))
    }

    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  defp snapshot(state) do
    %{
      active_games_count: MapSet.size(state.active_games),
      recent_games: state.recent_games
    }
  end
end
