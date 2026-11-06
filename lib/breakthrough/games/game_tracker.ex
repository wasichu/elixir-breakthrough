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
    {:ok,
     %{active_games: MapSet.new(), recent_games: [], game_summaries: %{}, game_monitors: %{}}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot(state), state}
  end

  @impl true
  def handle_cast({:track_game_started, game_id}, state) do
    state = monitor_game(state, game_id)

    next_state = %{
      state
      | active_games:
          if(Map.get(Map.get(state.game_summaries, game_id, %{}), :status) == :finished,
            do: state.active_games,
            else: MapSet.put(state.active_games, game_id)
          ),
        recent_games:
          [game_id | Enum.reject(state.recent_games, &(&1 == game_id))]
          |> Enum.take(@recent_limit),
        game_summaries: Map.put_new(state.game_summaries, game_id, default_summary(game_id))
    }

    next_state = prune_missing_game(next_state, game_id)
    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:track_game_updated, game_state}, state) do
    state = monitor_game(state, game_state.id)

    next_state =
      state
      |> put_in([:game_summaries, game_state.id], summarize_game(game_state))
      |> Map.update!(:active_games, fn games ->
        if game_state.game.status == :finished,
          do: MapSet.delete(games, game_state.id),
          else: MapSet.put(games, game_state.id)
      end)

    next_state = prune_missing_game(next_state, game_state.id)
    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:track_game_stopped, game_id}, state) do
    next_state = drop_game(state, game_id)

    Phoenix.PubSub.broadcast(Breakthrough.PubSub, @topic, {:lobby_updated, snapshot(next_state)})
    {:noreply, next_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Enum.find(Map.get(state, :game_monitors, %{}), fn {_id, monitored} ->
           monitored == {pid, ref}
         end) do
      {game_id, _monitor} ->
        next_state = drop_game(state, game_id)

        Phoenix.PubSub.broadcast(
          Breakthrough.PubSub,
          @topic,
          {:lobby_updated, snapshot(next_state)}
        )

        {:noreply, next_state}

      nil ->
        {:noreply, state}
    end
  end

  defp monitor_game(state, game_id) do
    monitors = Map.get(state, :game_monitors, %{})

    case Registry.lookup(Breakthrough.Games.Registry, game_id) do
      [{pid, _}] ->
        case Map.get(monitors, game_id) do
          {^pid, _ref} ->
            state

          previous ->
            if previous do
              {_old_pid, old_ref} = previous
              Process.demonitor(old_ref, [:flush])
            end

            Map.put(
              state,
              :game_monitors,
              Map.put(monitors, game_id, {pid, Process.monitor(pid)})
            )
        end

      [] ->
        # Monitoring a process which has already stopped immediately sends DOWN.
        # Register it only while its actual process is still discoverable.
        state
    end
  end

  defp prune_missing_game(state, game_id) do
    case Registry.lookup(Breakthrough.Games.Registry, game_id) do
      [] -> drop_game(state, game_id)
      [_entry] -> state
    end
  end

  defp drop_game(state, game_id) do
    {monitor, monitors} = Map.pop(Map.get(state, :game_monitors, %{}), game_id)

    if monitor do
      {_pid, ref} = monitor
      Process.demonitor(ref, [:flush])
    end

    state
    |> Map.put(:game_monitors, monitors)
    |> Map.update!(:active_games, &MapSet.delete(&1, game_id))
    |> Map.update!(:recent_games, &Enum.reject(&1, fn id -> id == game_id end))
    |> Map.update!(:game_summaries, &Map.delete(&1, game_id))
  end

  defp snapshot(state) do
    %{
      active_games_count: MapSet.size(state.active_games),
      recent_games: Enum.map(state.recent_games, &Map.fetch!(state.game_summaries, &1))
    }
  end

  defp default_summary(game_id) do
    %{id: game_id, mode: :pvp, full?: false, status: :not_started}
  end

  defp summarize_game(game_state) do
    %{
      id: game_state.id,
      mode: game_state.mode,
      status: game_state.game.status,
      full?: seat_claimed?(game_state.players.white) and seat_claimed?(game_state.players.black)
    }
  end

  defp seat_claimed?(player) when is_binary(player), do: true
  defp seat_claimed?(:ai), do: true
  defp seat_claimed?(_player), do: false
end
