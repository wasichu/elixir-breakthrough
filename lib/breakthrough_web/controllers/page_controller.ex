defmodule BreakthroughWeb.PageController do
  use BreakthroughWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
