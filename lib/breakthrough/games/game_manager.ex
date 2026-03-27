defmodule Breakthrough.Games.GameManager do
  @moduledoc false

  alias Breakthrough.Games.GameServer
  alias Breakthrough.Games.GameTracker

  def create_game(opts \\ []) do
    game_id = Keyword.get(opts, :id, random_id())
    mode = Keyword.get(opts, :mode, :pvp)
    cleanup_timeout_ms = Keyword.get(opts, :cleanup_timeout_ms)

    ensure_opts =
      [mode: mode]
      |> maybe_put_cleanup_timeout(cleanup_timeout_ms)

    with {:ok, _pid} <- ensure_game_started(game_id, ensure_opts) do
      {:ok, game_id}
    end
  end

  def ensure_game_started(game_id, opts \\ []) do
    mode = Keyword.get(opts, :mode, :pvp)
    cleanup_timeout_ms = Keyword.get(opts, :cleanup_timeout_ms)

    case Registry.lookup(Breakthrough.Games.Registry, game_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        child_spec =
          if cleanup_timeout_ms do
            {GameServer, id: game_id, mode: mode, cleanup_timeout_ms: cleanup_timeout_ms}
          else
            {GameServer, id: game_id, mode: mode}
          end

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
      GameServer.get_state(game_id)
    end
  end

  def join_game(game_id, player_token) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      GameServer.join_game(game_id, player_token)
    end
  end

  def make_move(game_id, player_token, from, to) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      GameServer.make_move(game_id, player_token, from, to)
    end
  end

  def track_connection(game_id, player_token, pid) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      GameServer.track_connection(game_id, player_token, pid)
    end
  end

  def resign(game_id, player_token) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      GameServer.resign(game_id, player_token)
    end
  end

  def restart_game(game_id) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      GameServer.restart_game(game_id)
    end
  end

  def set_mode(game_id, mode) do
    with {:ok, _pid} <- existing_game_pid(game_id) do
      GameServer.set_mode(game_id, mode)
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

  defp maybe_put_cleanup_timeout(opts, nil), do: opts

  defp maybe_put_cleanup_timeout(opts, cleanup_timeout_ms),
    do: Keyword.put(opts, :cleanup_timeout_ms, cleanup_timeout_ms)

  defp existing_game_pid(game_id) do
    case Registry.lookup(Breakthrough.Games.Registry, game_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
