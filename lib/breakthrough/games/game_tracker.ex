defmodule Breakthrough.Games.GameTracker do
  @moduledoc false
  use GenServer

  @topic "games:lobby"
  @recent_limit 5

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def track_game_started(game_id), do: GenServer.cast(__MODULE__, {:track_game_started, game_id})

  def track_game_updated(game_state),
    do: GenServer.cast(__MODULE__, {:track_game_updated, game_state})

  def track_game_stopped(game_id), do: GenServer.cast(__MODULE__, {:track_game_stopped, game_id})
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def topic, do: @topic

  @impl true
  def init(:ok) do
    {:ok, %{active_games: MapSet.new(), recent_games: [], game_summaries: %{}}}
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
        [game_id | Enum.reject(state.recent_games, &(&1 == game_id))] |> Enum.take(@recent_limit),
      game_summaries: Map.put_new(state.game_summaries, game_id, default_summary(game_id))
    }

    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:track_game_updated, game_state}, state) do
    next_state = put_in(state.game_summaries[game_state.id], summarize_game(game_state))

    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:track_game_stopped, game_id}, state) do
    next_state = %{
      active_games: MapSet.delete(state.active_games, game_id),
      recent_games: Enum.reject(state.recent_games, &(&1 == game_id)),
      game_summaries: Map.delete(state.game_summaries, game_id)
    }

    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  defp snapshot(state) do
    %{
      active_games_count: MapSet.size(state.active_games),
      recent_games: Enum.map(state.recent_games, &Map.fetch!(state.game_summaries, &1))
    }
  end

  defp default_summary(game_id) do
    %{id: game_id, mode: :pvp, full?: false}
  end

  defp summarize_game(game_state) do
    %{
      id: game_state.id,
      mode: game_state.mode,
      full?: seat_claimed?(game_state.players.white) and seat_claimed?(game_state.players.black)
    }
  end

  defp seat_claimed?(player) when is_binary(player), do: true
  defp seat_claimed?(:ai), do: true
  defp seat_claimed?(_player), do: false
end
