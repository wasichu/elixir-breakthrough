defmodule Breakthrough.Games.GameServer do
  @moduledoc false
  use GenServer, restart: :transient

  alias Breakthrough.Game
  alias Breakthrough.Games.GameTracker

  @cleanup_reason :inactive
  @default_cleanup_timeout_ms 5_000

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    mode = Keyword.get(opts, :mode, :pvp)
    cleanup_timeout_ms = Keyword.get(opts, :cleanup_timeout_ms, @default_cleanup_timeout_ms)

    GenServer.start_link(
      __MODULE__,
      %{id: id, mode: mode, cleanup_timeout_ms: cleanup_timeout_ms},
      name: via_tuple(id)
    )
  end

  def via_tuple(game_id) do
    {:via, Registry, {Breakthrough.Games.Registry, game_id}}
  end

  def get_state(game_id), do: GenServer.call(via_tuple(game_id), :get_state)

  def join_game(game_id, player_token),
    do: GenServer.call(via_tuple(game_id), {:join_game, player_token})

  def track_connection(game_id, player_token, pid) do
    GenServer.call(via_tuple(game_id), {:track_connection, player_token, pid})
  end

  def resign(game_id, player_token) do
    GenServer.call(via_tuple(game_id), {:resign, player_token})
  end

  def make_move(game_id, player_token, from, to) do
    GenServer.call(via_tuple(game_id), {:make_move, player_token, from, to})
  end

  def restart_game(game_id), do: GenServer.call(via_tuple(game_id), :restart_game)
  def set_mode(game_id, mode), do: GenServer.call(via_tuple(game_id), {:set_mode, mode})

  @impl true
  def init(%{id: id, mode: mode, cleanup_timeout_ms: cleanup_timeout_ms}) do
    {:ok,
     %{
       id: id,
       game: Game.new(),
       mode: mode,
       players: %{white: nil, black: nil},
       spectators: MapSet.new(),
       cleanup_timeout_ms: cleanup_timeout_ms,
       cleanup_timer_ref: nil,
       connections: %{}
     }}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, public_state(state)}, state}
  end

  def handle_call({:join_game, player_token}, _from, state) do
    {player_side, next_state} = join_player(state, player_token)
    broadcast_state(next_state)
    {:reply, {:ok, player_side, public_state(next_state)}, next_state}
  end

  def handle_call({:track_connection, player_token, pid}, _from, state) do
    next_state =
      state
      |> put_connection(player_token, pid)
      |> cancel_cleanup_if_needed()

    broadcast_state(next_state)
    {:reply, {:ok, public_state(next_state)}, next_state}
  end

  def handle_call({:make_move, player_token, from, to}, _from, state) do
    with {:ok, player_side} <- player_side_for(state, player_token),
         :ok <- ensure_active_game(state.game),
         :ok <- ensure_turn(state.game, player_side),
         {:ok, next_game} <- Game.move(state.game, from, to) do
      next_state = %{state | game: next_game} |> maybe_trigger_ai()
      broadcast_state(next_state)
      {:reply, {:ok, public_state(next_state)}, next_state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:resign, player_token}, _from, state) do
    with {:ok, player_side} <- player_side_for(state, player_token),
         :ok <- ensure_active_game(state.game),
         {:ok, next_game} <- Game.resign(state.game, player_side) do
      next_state = %{state | game: next_game}
      broadcast_state(next_state)
      {:reply, {:ok, public_state(next_state)}, next_state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:restart_game, _from, state) do
    next_state =
      state
      |> Map.put(:game, Game.new())
      |> maybe_trigger_ai()
      |> cancel_cleanup_if_needed()

    broadcast_state(next_state)
    {:reply, {:ok, public_state(next_state)}, next_state}
  end

  def handle_call({:set_mode, mode}, _from, state) do
    next_state = %{state | mode: mode} |> maybe_trigger_ai()
    broadcast_state(next_state)
    {:reply, {:ok, public_state(next_state)}, next_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    next_state =
      state
      |> drop_connection(pid, ref)
      |> maybe_schedule_cleanup()

    broadcast_state(next_state)
    {:noreply, next_state}
  end

  def handle_info(:expire_if_inactive, state) do
    state = %{state | cleanup_timer_ref: nil}

    if should_expire?(state) do
      Phoenix.PubSub.broadcast(
        Breakthrough.PubSub,
        topic(state.id),
        {:game_expired, @cleanup_reason}
      )

      GameTracker.track_game_stopped(state.id)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp join_player(state, player_token) do
    cond do
      state.players.white == player_token ->
        {:white, state}

      state.players.black == player_token ->
        {:black, state}

      is_nil(state.players.white) ->
        {:white, put_in(state.players.white, player_token)}

      is_nil(state.players.black) ->
        {:black, put_in(state.players.black, player_token)}

      true ->
        {:spectator, update_in(state.spectators, &MapSet.put(&1, player_token))}
    end
  end

  defp player_side_for(state, player_token) do
    cond do
      state.players.white == player_token -> {:ok, :white}
      state.players.black == player_token -> {:ok, :black}
      true -> {:error, :spectator}
    end
  end

  defp connection_side(state, player_token) do
    case player_side_for(state, player_token) do
      {:ok, side} -> side
      {:error, :spectator} -> :spectator
    end
  end

  defp put_connection(state, player_token, pid) do
    if Map.has_key?(state.connections, pid) do
      state
    else
      ref = Process.monitor(pid)
      side = connection_side(state, player_token)
      put_in(state.connections[pid], %{ref: ref, token: player_token, side: side})
    end
  end

  defp drop_connection(state, pid, ref) do
    case Map.get(state.connections, pid) do
      %{ref: ^ref} ->
        update_in(state.connections, &Map.delete(&1, pid))

      _other ->
        state
    end
  end

  defp ensure_active_game(%{winner: winner}) when winner in [:white, :black],
    do: {:error, :game_over}

  defp ensure_active_game(_game), do: :ok

  defp ensure_turn(%{current_player: current_player}, current_player), do: :ok
  defp ensure_turn(_game, _side), do: {:error, :not_your_turn}

  defp maybe_trigger_ai(%{mode: :vs_ai} = state) do
    state
  end

  defp maybe_trigger_ai(state), do: state

  defp maybe_schedule_cleanup(state) do
    cond do
      state.cleanup_timer_ref ->
        state

      should_expire?(state) ->
        %{
          state
          | cleanup_timer_ref:
              Process.send_after(self(), :expire_if_inactive, state.cleanup_timeout_ms)
        }

      true ->
        state
    end
  end

  defp cancel_cleanup_if_needed(state) do
    if state.cleanup_timer_ref && not should_expire?(state) do
      Process.cancel_timer(state.cleanup_timer_ref)
      %{state | cleanup_timer_ref: nil}
    else
      state
    end
  end

  defp should_expire?(state) do
    started_game?(state.game) and not player_connected?(state, :white) and
      not player_connected?(state, :black)
  end

  defp started_game?(%{move_history: move_history}), do: move_history != []

  defp player_connected?(state, side) when side in [:white, :black] do
    Enum.any?(state.connections, fn {_pid, connection} -> connection.side == side end)
  end

  defp spectator_count(state) do
    state.connections
    |> Enum.reduce(MapSet.new(), fn {_pid, connection}, spectators ->
      if connection.side == :spectator do
        MapSet.put(spectators, connection.token)
      else
        spectators
      end
    end)
    |> MapSet.size()
  end

  defp player_presence(state) do
    %{
      white: player_connected?(state, :white),
      black: player_connected?(state, :black)
    }
  end

  defp public_state(state) do
    %{
      id: state.id,
      game: state.game,
      mode: state.mode,
      players: state.players,
      player_presence: player_presence(state),
      spectator_count: spectator_count(state)
    }
  end

  defp broadcast_state(state) do
    Phoenix.PubSub.broadcast(
      Breakthrough.PubSub,
      topic(state.id),
      {:game_updated, public_state(state)}
    )
  end

  def topic(game_id), do: "game:#{game_id}"
end
