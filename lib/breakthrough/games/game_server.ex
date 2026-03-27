defmodule Breakthrough.Games.GameServer do
  @moduledoc false
  use GenServer, restart: :transient

  alias Breakthrough.Game
  alias Breakthrough.GameAI.ScoredStrategy
  alias Breakthrough.Games.GameTracker

  @cleanup_reason :inactive
  @ready_cleanup_reason :unstarted
  @move_cleanup_reason :stalled
  @default_pvp_cleanup_timeout_ms 10_000
  @default_ai_cleanup_timeout_ms 5_000
  @default_pvp_ready_timeout_ms 60_000
  @default_move_timeout_ms 1_200_000
  @ai_token :ai
  @ai_player :black

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    mode = Keyword.get(opts, :mode, :pvp)
    cleanup_timeout_ms = Keyword.get(opts, :cleanup_timeout_ms, default_cleanup_timeout_ms(mode))
    ready_timeout_ms = Keyword.get(opts, :ready_timeout_ms, default_ready_timeout_ms(mode))
    move_timeout_ms = Keyword.get(opts, :move_timeout_ms, @default_move_timeout_ms)
    ai_strategy = Keyword.get(opts, :ai_strategy, ScoredStrategy)
    players = Keyword.get(opts, :players)

    GenServer.start_link(
      __MODULE__,
      %{
        id: id,
        mode: mode,
        cleanup_timeout_ms: cleanup_timeout_ms,
        ready_timeout_ms: ready_timeout_ms,
        move_timeout_ms: move_timeout_ms,
        ai_strategy: ai_strategy,
        players: players
      },
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

  def create_rematch(game_id, player_token) do
    GenServer.call(via_tuple(game_id), {:create_rematch, player_token})
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
  def init(%{
        id: id,
        mode: mode,
        cleanup_timeout_ms: cleanup_timeout_ms,
        ready_timeout_ms: ready_timeout_ms,
        move_timeout_ms: move_timeout_ms,
        ai_strategy: ai_strategy,
        players: players
      }) do
    state = %{
      id: id,
      game: Game.new(),
      mode: mode,
      players: players || initial_players(mode),
      spectators: MapSet.new(),
      cleanup_timeout_ms: cleanup_timeout_ms,
      cleanup_timer_ref: nil,
      ready_timeout_ms: ready_timeout_ms,
      ready_timer_ref: nil,
      move_timeout_ms: move_timeout_ms,
      move_timer_ref: nil,
      connections: %{},
      ai_strategy: ai_strategy,
      rematch_votes: MapSet.new()
    }

    state = maybe_schedule_ready_timeout(state)

    GameTracker.track_game_updated(public_state(state))
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, public_state(state)}, state}
  end

  def handle_call({:join_game, player_token}, _from, state) do
    {player_side, next_state} =
      state
      |> join_player(player_token)
      |> then(fn {side, joined_state} -> {side, maybe_schedule_ready_timeout(joined_state)} end)

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

  def handle_call({:create_rematch, player_token}, _from, state) do
    with {:ok, player_side} <- player_side_for(state, player_token),
         :ok <- ensure_finished_game(state.game) do
      case maybe_create_rematch(state, player_side) do
        {:pending, next_state} ->
          broadcast_state(next_state)
          {:reply, {:pending, public_state(next_state)}, next_state}

        {:ok, game_id, next_state} ->
          Phoenix.PubSub.broadcast(
            Breakthrough.PubSub,
            topic(state.id),
            {:rematch_created, game_id}
          )

          {:reply, {:ok, game_id}, next_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:make_move, player_token, from, to}, _from, state) do
    with {:ok, player_side} <- player_side_for(state, player_token),
         :ok <- ensure_active_game(state.game),
         :ok <- ensure_turn(state.game, player_side),
         {:ok, next_game} <- Game.move(state.game, from, to) do
      next_state =
        %{state | game: next_game, rematch_votes: MapSet.new()}
        |> cancel_ready_timeout()
        |> maybe_trigger_ai()
        |> restart_move_timeout()

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
      next_state =
        %{state | game: next_game, rematch_votes: MapSet.new()}
        |> cancel_ready_timeout()
        |> restart_move_timeout()

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
      |> Map.put(:rematch_votes, MapSet.new())
      |> cancel_ready_timeout()
      |> cancel_move_timeout()
      |> maybe_trigger_ai()
      |> maybe_schedule_ready_timeout()
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

  def handle_info(:expire_if_unstarted, state) do
    state = %{state | ready_timer_ref: nil}

    if should_expire_unstarted?(state) do
      Phoenix.PubSub.broadcast(
        Breakthrough.PubSub,
        topic(state.id),
        {:game_expired, @ready_cleanup_reason}
      )

      GameTracker.track_game_stopped(state.id)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:expire_if_stalled, state) do
    state = %{state | move_timer_ref: nil}

    if should_expire_for_move_inactivity?(state) do
      Phoenix.PubSub.broadcast(
        Breakthrough.PubSub,
        topic(state.id),
        {:game_expired, @move_cleanup_reason}
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

  defp ensure_finished_game(%{winner: winner}) when winner in [:white, :black], do: :ok
  defp ensure_finished_game(_game), do: {:error, :not_finished}

  defp ensure_turn(%{current_player: current_player}, current_player), do: :ok
  defp ensure_turn(_game, _side), do: {:error, :not_your_turn}

  defp maybe_trigger_ai(%{mode: :vs_ai} = state) do
    with true <- state.game.current_player == @ai_player,
         :ok <- ensure_active_game(state.game),
         {:ok, %{from: from, to: to}} <- state.ai_strategy.choose_move(state.game, @ai_player),
         {:ok, next_game} <- Game.move(state.game, from, to) do
      %{state | game: next_game}
    else
      false ->
        state

      {:error, :no_legal_moves} ->
        %{
          state
          | game: %{state.game | winner: :white, status: :finished}
        }

      {:error, :game_over} ->
        state
    end
  end

  defp maybe_trigger_ai(state), do: state

  defp maybe_create_rematch(%{mode: :vs_ai} = state, :white) do
    with {:ok, game_id} <- Breakthrough.Games.GameManager.create_game(rematch_game_opts(state)) do
      {:ok, game_id, %{state | rematch_votes: MapSet.new()}}
    end
  end

  defp maybe_create_rematch(%{mode: :pvp} = state, player_side) do
    next_state = %{state | rematch_votes: MapSet.put(state.rematch_votes, player_side)}

    if MapSet.size(next_state.rematch_votes) == 2 do
      with {:ok, game_id} <- Breakthrough.Games.GameManager.create_game(rematch_game_opts(state)) do
        {:ok, game_id, %{next_state | rematch_votes: MapSet.new()}}
      end
    else
      {:pending, next_state}
    end
  end

  defp rematch_game_opts(%{mode: :vs_ai, ai_strategy: ai_strategy, players: players}) do
    [
      mode: :vs_ai,
      ai_strategy: ai_strategy,
      players: %{white: players.white, black: @ai_token}
    ]
  end

  defp rematch_game_opts(%{mode: :pvp, ai_strategy: ai_strategy, players: players}) do
    [
      mode: :pvp,
      ai_strategy: ai_strategy,
      players: %{white: players.black, black: players.white}
    ]
  end

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

  defp maybe_schedule_ready_timeout(state) do
    cond do
      state.ready_timeout_ms <= 0 ->
        state

      state.ready_timer_ref ->
        state

      should_expire_unstarted?(state) ->
        %{
          state
          | ready_timer_ref:
              Process.send_after(self(), :expire_if_unstarted, state.ready_timeout_ms)
        }

      true ->
        state
    end
  end

  defp restart_move_timeout(state) do
    state
    |> cancel_move_timeout()
    |> maybe_schedule_move_timeout()
  end

  defp maybe_schedule_move_timeout(state) do
    cond do
      state.move_timeout_ms <= 0 ->
        state

      state.move_timer_ref ->
        state

      should_expire_for_move_inactivity?(state) ->
        %{
          state
          | move_timer_ref: Process.send_after(self(), :expire_if_stalled, state.move_timeout_ms)
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

  defp cancel_ready_timeout(%{ready_timer_ref: nil} = state), do: state

  defp cancel_ready_timeout(state) do
    Process.cancel_timer(state.ready_timer_ref)
    %{state | ready_timer_ref: nil}
  end

  defp cancel_move_timeout(%{move_timer_ref: nil} = state), do: state

  defp cancel_move_timeout(state) do
    Process.cancel_timer(state.move_timer_ref)
    %{state | move_timer_ref: nil}
  end

  defp should_expire?(state) do
    case state.mode do
      :vs_ai -> ai_game_abandoned?(state)
      :pvp -> pvp_game_abandoned?(state)
    end
  end

  defp should_expire_unstarted?(state) do
    state.mode == :pvp and not started_game?(state.game) and both_human_seats_claimed?(state)
  end

  defp should_expire_for_move_inactivity?(state) do
    started_game?(state.game)
  end

  defp started_game?(%{move_history: move_history}), do: move_history != []

  defp default_cleanup_timeout_ms(:vs_ai), do: @default_ai_cleanup_timeout_ms
  defp default_cleanup_timeout_ms(_mode), do: @default_pvp_cleanup_timeout_ms
  defp default_ready_timeout_ms(:pvp), do: @default_pvp_ready_timeout_ms
  defp default_ready_timeout_ms(_mode), do: 0

  defp player_connected?(state, side) when side in [:white, :black] do
    if state.players[side] == @ai_token do
      true
    else
      Enum.any?(state.connections, fn {_pid, connection} -> connection.side == side end)
    end
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

  defp pvp_game_abandoned?(state) do
    started_game?(state.game) and both_human_seats_claimed?(state) and
      human_players_disconnected?(state)
  end

  defp ai_game_abandoned?(state) do
    is_binary(state.players.white) and not player_connected?(state, :white)
  end

  defp both_human_seats_claimed?(state) do
    is_binary(state.players.white) and is_binary(state.players.black)
  end

  defp human_players_disconnected?(state) do
    [:white, :black]
    |> Enum.filter(fn side -> is_binary(state.players[side]) end)
    |> Enum.all?(fn side -> not player_connected?(state, side) end)
  end

  defp initial_players(:vs_ai), do: %{white: nil, black: @ai_token}
  defp initial_players(_mode), do: %{white: nil, black: nil}

  defp public_state(state) do
    %{
      id: state.id,
      game: state.game,
      mode: state.mode,
      players: state.players,
      player_presence: player_presence(state),
      spectator_count: spectator_count(state),
      rematch_votes: state.rematch_votes
    }
  end

  defp broadcast_state(state) do
    GameTracker.track_game_updated(public_state(state))

    Phoenix.PubSub.broadcast(
      Breakthrough.PubSub,
      topic(state.id),
      {:game_updated, public_state(state)}
    )
  end

  def topic(game_id), do: "game:#{game_id}"
end
