defmodule BreakthroughWeb.Plugs.EnsurePlayerToken do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, "player_token") do
      nil -> put_session(conn, "player_token", random_token())
      _token -> conn
    end
  end

  defp random_token do
    12
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
