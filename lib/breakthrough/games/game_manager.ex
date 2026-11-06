defmodule Breakthrough.Games.GameManager do
  @moduledoc false

  alias Breakthrough.Games.GameServer
  alias Breakthrough.Games.GameTracker

  @game_server_option_keys [
    :mode,
    :cleanup_timeout_ms,
    :waiting_timeout_ms,
    :ready_timeout_ms,
    :move_timeout_ms,
    :finished_timeout_ms,
    :ai_strategy,
    :players,
    :creator_token
  ]

  def create_game(opts \\ []) do
    game_id = Keyword.get(opts, :id, random_id())

    with {:ok, _pid} <- ensure_game_started(game_id, game_server_opts(opts)) do
      {:ok, game_id}
    end
  end

  def ensure_game_started(game_id, opts \\ []) do
    game_server_opts = game_server_opts(opts)

    case Registry.lookup(Breakthrough.Games.Registry, game_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        child_spec = {GameServer, Keyword.put(game_server_opts, :id, game_id)}

        case DynamicSupervisor.start_child(Breakthrough.Games.GameSupervisor, child_spec) do
          {:ok, _pid} = result ->
            GameTracker.track_game_started(game_id)
            result

          {:error, {:already_started, _pid}} = result ->
            GameTracker.track_game_started(game_id)
            result

          other ->
            other
        end
    end
  end

  def get_state(game_id) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.get_state(game_id) end)
    end
  end

  def join_game(game_id, player_token) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.join_game(game_id, player_token) end)
    end
  end

  def make_move(game_id, player_token, from, to) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.make_move(game_id, player_token, from, to) end)
    end
  end

  def track_connection(game_id, player_token, pid) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.track_connection(game_id, player_token, pid) end)
    end
  end

  def cancel_game(game_id, player_token) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.cancel_game(game_id, player_token) end)
    end
  end

  def get_created_game(player_token) when is_binary(player_token) do
    case Registry.lookup(Breakthrough.Games.Registry, {:game_creator, player_token}) do
      [{pid, _game_id}] -> call_if_alive(fn -> GenServer.call(pid, :get_state) end)
      [] -> {:error, :not_found}
    end
  end

  def resign(game_id, player_token) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.resign(game_id, player_token) end)
    end
  end

  def create_rematch(game_id, player_token) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.create_rematch(game_id, player_token) end)
    end
  end

  def restart_game(game_id) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.restart_game(game_id) end)
    end
  end

  def set_mode(game_id, mode) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      call_if_alive(fn -> GameServer.set_mode(game_id, mode) end)
    end
  end

  def lobby_snapshot do
    GameTracker.snapshot()
  end

  defp random_id do
    6
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 8)
  end

  defp game_server_opts(opts) do
    opts
    |> Keyword.take(@game_server_option_keys)
    |> Keyword.put_new(:mode, :pvp)
  end

  defp existing_game_pid(game_id) do
    case Registry.lookup(Breakthrough.Games.Registry, game_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp call_if_alive(fun) do
    fun.()
  catch
    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] ->
      {:error, :not_found}
  end
end
