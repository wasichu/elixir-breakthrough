defmodule BreakthroughWeb.HomeLobbyTest do
  # The recent-game list is global and capped, so concurrent creation changes it.
  use BreakthroughWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "home page shows lobby counts and recent game links", %{conn: conn} do
    first_game = "recent-" <> Integer.to_string(System.unique_integer([:positive]))
    second_game = "recent-" <> Integer.to_string(System.unique_integer([:positive]))
    ai_game = "recent-ai-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, _first} = Breakthrough.Games.GameManager.create_game(id: first_game)
    {:ok, _second} = Breakthrough.Games.GameManager.create_game(id: second_game)
    {:ok, _ai} = Breakthrough.Games.GameManager.create_game(id: ai_game, mode: :vs_ai)
    {:ok, :white, _state} = Breakthrough.Games.GameManager.join_game(first_game, "lobby-white")
    {:ok, :black, _state} = Breakthrough.Games.GameManager.join_game(first_game, "lobby-black")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#active-games-count")
    assert has_element?(view, ~s(a[href="/games/#{first_game}"]))
    assert has_element?(view, ~s(a[href="/games/#{second_game}"]))
    assert has_element?(view, ~s(a[href="/games/#{ai_game}"]))
    assert has_element?(view, ~s(a[href="/games/#{ai_game}"]), ai_game)
    assert has_element?(view, "#lobby-ai-#{ai_game}", "AI")
    assert has_element?(view, ~s(a[href="/games/#{first_game}"] span), "View game")
    assert has_element?(view, ~s(a[href="/games/#{second_game}"] span), "Join game")
  end

  test "lobby shows an owned waiting game and explains both blocked create actions", %{conn: conn} do
    {conn, game_id, _token} = waiting_game(conn)
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#current-created-game[data-game-id='#{game_id}']")
    assert has_element?(view, "#cancel-current-game-button")

    for button <- ["#create-game-button", "#create-ai-game-button"] do
      view |> element(button) |> render_click()
      refute_redirected(view)
      assert has_element?(view, "#new-game-notice[role='status']", "A new game wasn’t created")
    end
  end

  test "waiting game can be cancelled from the lobby before creating an AI game", %{conn: conn} do
    {conn, game_id, token} = waiting_game(conn)
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#cancel-current-game-button") |> render_click()
    assert has_element?(view, "#home-info-banner", "Waiting game cancelled")
    refute has_element?(view, "#current-created-game")
    assert {:error, :not_found} = Breakthrough.Games.GameManager.get_state(game_id)
    assert {:error, :not_found} = Breakthrough.Games.GameManager.get_created_game(token)
    view |> element("#create-ai-game-button") |> render_click()
    {path, _flash} = assert_redirect(view)
    refute path == ~p"/games/#{game_id}"
  end

  test "lobby removes cancellation when an opponent joins", %{conn: conn} do
    {conn, game_id, _token} = waiting_game(conn)
    {:ok, view, _html} = live(conn, ~p"/")
    {:ok, :black, _state} = Breakthrough.Games.GameManager.join_game(game_id, "joined-opponent")

    assert_eventually(fn ->
      assert has_element?(view, "#current-game-title", "multiplayer game in progress")
      refute has_element?(view, "#cancel-current-game-button")
    end)

    render_hook(view, "cancel-current-game", %{"id" => game_id})
    assert has_element?(view, "#home-info-banner", "Your opponent has joined")
    assert {:ok, _state} = Breakthrough.Games.GameManager.get_state(game_id)
  end

  test "a cancellation request cannot target someone else's game", %{conn: conn} do
    {conn, owned_id, _token} = waiting_game(conn)

    {:ok, other_id} =
      Breakthrough.Games.GameManager.create_game(
        creator_token: "other-#{System.unique_integer([:positive])}"
      )

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "cancel-current-game", %{"id" => other_id})
    assert {:ok, _} = Breakthrough.Games.GameManager.get_state(owned_id)
    assert {:ok, _} = Breakthrough.Games.GameManager.get_state(other_id)
    assert has_element?(view, "#current-created-game[data-game-id='#{owned_id}']")
  end

  test "stale cancellation does not cancel a newer game created in another tab", %{conn: conn} do
    {conn, old_id, token} = waiting_game(conn)
    {:ok, view, _html} = live(conn, ~p"/")
    :ok = Breakthrough.Games.GameManager.cancel_game(old_id, token)
    {:ok, new_id} = Breakthrough.Games.GameManager.create_game(creator_token: token)
    render_hook(view, "cancel-current-game", %{"id" => old_id})
    assert {:ok, _} = Breakthrough.Games.GameManager.get_state(new_id)
    assert has_element?(view, "#current-created-game[data-game-id='#{new_id}']")
  end

  test "the current-game section disappears once the game finishes", %{conn: conn} do
    token = "ai-owner-#{System.unique_integer([:positive])}"
    conn = Plug.Test.init_test_session(conn, %{"player_token" => token})

    {:ok, game_id} =
      Breakthrough.Games.GameManager.create_game(creator_token: token, mode: :vs_ai)

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#current-game-title", "AI game in progress")
    refute has_element?(view, "#cancel-current-game-button")
    view |> element("#create-ai-game-button") |> render_click()
    assert has_element?(view, "#new-game-notice")
    {:ok, _} = Breakthrough.Games.GameManager.resign(game_id, token)

    assert_eventually(fn ->
      refute has_element?(view, "#current-created-game")
      refute has_element?(view, "#new-game-notice")
    end)
  end

  defp assert_eventually(assertion, attempts \\ 50) do
    assertion.()
  rescue
    error in ExUnit.AssertionError ->
      if attempts > 1 do
        Process.sleep(10)
        assert_eventually(assertion, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp waiting_game(conn) do
    token = "lobby-owner-#{System.unique_integer([:positive])}"
    conn = Plug.Test.init_test_session(conn, %{"player_token" => token})
    {:ok, game_id} = Breakthrough.Games.GameManager.create_game(creator_token: token)
    {conn, game_id, token}
  end
end
