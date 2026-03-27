defmodule BreakthroughWeb.GameLiveTest do
  use BreakthroughWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "root page shows the new game control", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#create-game-button")
    assert has_element?(view, "#create-ai-game-button")
    assert has_element?(view, "#view-rules-button")
  end

  test "home page opens and closes the rules modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#rules-modal")

    view
    |> element("#view-rules-button")
    |> render_click()

    assert has_element?(view, "#rules-modal")
    assert has_element?(view, "#close-rules-button")

    view
    |> element("#close-rules-button")
    |> render_click()

    refute has_element?(view, "#rules-modal")
  end

  test "home page renders a styled unavailable-game banner from flash", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> Phoenix.ConnTest.put_flash(:error, "That game is no longer available.")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-error-banner", "That game is no longer available.")
    refute has_element?(view, "#flash-error")
  end

  test "clicking new game redirects to a unique game url", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#create-game-button")
    |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r"^/games/[A-Za-z0-9_-]+$"
  end

  test "clicking play vs ai redirects to a unique game url", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#create-ai-game-button")
    |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r"^/games/[A-Za-z0-9_-]+$"
  end

  test "game route renders board and assigns first visitor to white", %{conn: conn} do
    game_id = create_game!()
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    assert has_element?(view, "#breakthrough-board")
    assert has_element?(view, "#player-side-value[data-side='white']")
    assert has_element?(view, "#white-seat-status", "White: You")
    assert has_element?(view, "#black-seat-status", "Black: Open")
    assert has_element?(view, "#spectator-count", "Spectators: 0")
    assert has_element?(view, "#game-share-link[readonly]")
    assert has_element?(view, "#copy-link-button")
    assert has_element?(view, "#share-link-panel")
    assert has_element?(view, "#square-a2[data-piece='B']")
    assert has_element?(view, "#square-a7[data-piece='W']")
    refute has_element?(view, "#interaction-state")
    refute has_element?(view, "#selected-square-value")
  end

  test "second distinct session joining the same game becomes black", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-token"})
    black_conn = Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-token"})

    {:ok, white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, black_view, _html} = live(black_conn, ~p"/games/#{game_id}")

    assert has_element?(white_view, "#player-side-value[data-side='white']")
    assert has_element?(black_view, "#player-side-value[data-side='black']")
    assert has_element?(white_view, "#white-seat-status", "White: You")
    assert has_element?(white_view, "#black-seat-status", "Black: Claimed")
    assert has_element?(black_view, "#white-seat-status", "White: Claimed")
    assert has_element?(black_view, "#black-seat-status", "Black: You")
    assert has_element?(white_view, "#players-panel")
    assert has_element?(black_view, "#players-panel")
    assert has_element?(black_view, "#square-a2[disabled]")

    assert has_element?(
             black_view,
             "#breakthrough-board > div:first-child > button:first-of-type#square-h8"
           )

    assert has_element?(
             black_view,
             "#breakthrough-board > div:last-child > button:last-of-type#square-a1"
           )
  end

  test "third distinct session is counted as a spectator", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-spectator-count"})

    black_conn =
      Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-spectator-count"})

    spectator_conn =
      Plug.Test.init_test_session(build_conn(), %{"player_token" => "spectator-count"})

    {:ok, _white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, _black_view, _html} = live(black_conn, ~p"/games/#{game_id}")
    {:ok, spectator_view, _html} = live(spectator_conn, ~p"/games/#{game_id}")

    assert has_element?(spectator_view, "#player-side-value[data-side='spectator']")
    assert has_element?(spectator_view, "#spectator-count", "Spectators: 1")
    assert has_element?(spectator_view, "#white-seat-status", "White: Claimed")
    assert has_element?(spectator_view, "#black-seat-status", "Black: Claimed")
  end

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
    assert has_element?(view, ~s(a[href="/games/#{ai_game}"] span.rounded-full))
    assert has_element?(view, ~s(a[href="/games/#{first_game}"] span), "View game")
    assert has_element?(view, ~s(a[href="/games/#{second_game}"] span), "Join game")
  end

  test "selecting another current turn piece replaces the previous selection", %{conn: conn} do
    game_id = create_game!()
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    view
    |> element("#square-a7")
    |> render_click()

    assert has_element?(view, "#square-a7[data-selected='true']")
    assert has_element?(view, "#square-a6.ring-2")
    assert has_element?(view, "#square-b6.ring-2")

    view
    |> element("#square-b7")
    |> render_click()

    assert has_element?(view, "#square-a7[data-selected='false']")
    assert has_element?(view, "#square-b7[data-selected='true']")
    assert has_element?(view, "#square-a6.ring-2")
    assert has_element?(view, "#square-b6.ring-2")
    assert has_element?(view, "#square-c6.ring-2")
  end

  test "clicking a dead square clears the current selection without selecting it", %{conn: conn} do
    game_id = create_game!()
    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    view
    |> element("#square-a7")
    |> render_click()

    assert has_element?(view, "#square-a7[data-selected='true']")
    assert has_element?(view, "#square-a6.ring-2")

    view
    |> element("#square-d4")
    |> render_click()

    assert has_element?(view, "#square-a7[data-selected='false']")
    assert has_element?(view, "#square-d4[data-selected='false']")
    refute has_element?(view, "#square-a6.ring-2")
    refute has_element?(view, "#square-b6.ring-2")
  end

  test "a player cannot select pieces when it is not their turn", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-turn"})
    black_conn = Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-turn"})

    {:ok, _white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, black_view, _html} = live(black_conn, ~p"/games/#{game_id}")

    assert has_element?(black_view, "#square-a2[disabled]")
    refute has_element?(black_view, "#square-a2[data-selected='true']")
  end

  test "last move is highlighted for both players", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-last-move"})
    black_conn = Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-last-move"})

    {:ok, white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, black_view, _html} = live(black_conn, ~p"/games/#{game_id}")

    white_view
    |> element("#square-a7")
    |> render_click()

    white_view
    |> element("#square-a6")
    |> render_click()

    assert has_element?(white_view, "#square-a7[data-last-move='true']")
    assert has_element?(white_view, "#square-a6[data-last-move='true']")
    assert has_element?(black_view, "#square-a7[data-last-move='true']")
    assert has_element?(black_view, "#square-a6[data-last-move='true']")
  end

  test "the UI shows when a claimed player disconnects", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-disconnect"})

    {:ok, white_view, _html} = live(white_conn, ~p"/games/#{game_id}")

    {:ok, :black, _state} =
      Breakthrough.Games.GameManager.join_game(game_id, "black-disconnect")

    black_pid = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, _state} =
             Breakthrough.Games.GameManager.track_connection(
               game_id,
               "black-disconnect",
               black_pid
             )

    white_view
    |> element("#square-a7")
    |> render_click()

    white_view
    |> element("#square-a6")
    |> render_click()

    Process.exit(black_pid, :kill)

    assert_eventually(fn ->
      assert has_element?(white_view, "#black-seat-status", "Black: Disconnected")
      assert has_element?(white_view, "#presence-note", "Black disconnected.")
    end)
  end

  test "an unknown or expired game url redirects home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/games/does-not-exist")
  end

  test "players can resign from an active game", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-resign"})
    black_conn = Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-resign"})

    {:ok, white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, black_view, _html} = live(black_conn, ~p"/games/#{game_id}")

    white_view
    |> element("#square-a7")
    |> render_click()

    white_view
    |> element("#square-a6")
    |> render_click()

    assert has_element?(white_view, "#resign-game-button")

    white_view
    |> element("#resign-game-button")
    |> render_click()

    assert has_element?(white_view, "#phase-value[data-phase='You lost']")
    assert has_element?(black_view, "#phase-value[data-phase='You won']")
    assert has_element?(white_view, "#finish-note", "You resigned.")
    assert has_element?(black_view, "#finish-note", "White resigned.")
    refute has_element?(white_view, "#resign-game-button")
  end

  test "spectators still see which side won after the game ends", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-spectator-win"})

    black_conn =
      Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-spectator-win"})

    spectator_conn =
      Plug.Test.init_test_session(build_conn(), %{"player_token" => "spectator-spectator-win"})

    {:ok, white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, _black_view, _html} = live(black_conn, ~p"/games/#{game_id}")
    {:ok, spectator_view, _html} = live(spectator_conn, ~p"/games/#{game_id}")

    white_view
    |> element("#square-a7")
    |> render_click()

    white_view
    |> element("#square-a6")
    |> render_click()

    white_view
    |> element("#resign-game-button")
    |> render_click()

    assert has_element?(spectator_view, "#phase-value[data-phase='Black wins']")
  end

  test "rematch redirects both players and spectators to a fresh game", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-rematch"})
    black_conn = Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-rematch"})

    spectator_conn =
      Plug.Test.init_test_session(build_conn(), %{"player_token" => "spectator-rematch"})

    {:ok, white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, black_view, _html} = live(black_conn, ~p"/games/#{game_id}")
    {:ok, spectator_view, _html} = live(spectator_conn, ~p"/games/#{game_id}")

    white_view
    |> element("#square-a7")
    |> render_click()

    white_view
    |> element("#square-a6")
    |> render_click()

    white_view
    |> element("#resign-game-button")
    |> render_click()

    assert has_element?(white_view, "#rematch-game-button")
    refute has_element?(black_view, "#rematch-pending-indicator")

    white_view
    |> element("#rematch-game-button")
    |> render_click()

    assert has_element?(white_view, "#rematch-pending-indicator")
    assert has_element?(white_view, "#rematch-note", "Waiting for Black to accept rematch.")
    assert has_element?(black_view, "#rematch-game-button")
    assert has_element?(black_view, "#rematch-note", "White requested a rematch.")
    refute_redirected(white_view)
    refute_redirected(black_view)
    refute_redirected(spectator_view)

    black_view
    |> element("#rematch-game-button")
    |> render_click()

    {white_path, _flash} = assert_redirect(white_view)
    {black_path, _flash} = assert_redirect(black_view)
    {spectator_path, _flash} = assert_redirect(spectator_view)

    assert white_path =~ ~r"^/games/[A-Za-z0-9_-]+$"
    assert white_path == black_path
    assert white_path == spectator_path
    refute white_path == "/games/#{game_id}"

    {:ok, rematch_white_view, _html} = live(white_conn, white_path)
    {:ok, rematch_black_view, _html} = live(black_conn, black_path)

    assert has_element?(rematch_white_view, "#player-side-value[data-side='black']")
    assert has_element?(rematch_black_view, "#player-side-value[data-side='white']")
  end

  test "spectators do not get a rematch button after the game ends", %{conn: conn} do
    game_id = create_game!()
    white_conn = Plug.Test.init_test_session(conn, %{"player_token" => "white-no-rematch"})

    black_conn =
      Plug.Test.init_test_session(build_conn(), %{"player_token" => "black-no-rematch"})

    spectator_conn =
      Plug.Test.init_test_session(build_conn(), %{"player_token" => "spectator-no-rematch"})

    {:ok, white_view, _html} = live(white_conn, ~p"/games/#{game_id}")
    {:ok, _black_view, _html} = live(black_conn, ~p"/games/#{game_id}")
    {:ok, spectator_view, _html} = live(spectator_conn, ~p"/games/#{game_id}")

    white_view
    |> element("#square-a7")
    |> render_click()

    white_view
    |> element("#square-a6")
    |> render_click()

    white_view
    |> element("#resign-game-button")
    |> render_click()

    assert has_element?(white_view, "#rematch-game-button")
    refute has_element?(spectator_view, "#rematch-game-button")
  end

  test "vs ai games show the ai seat and process an ai reply move", %{conn: conn} do
    game_id = "ai-live-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, ^game_id} =
      Breakthrough.Games.GameManager.create_game(
        id: game_id,
        mode: :vs_ai,
        ai_strategy: Breakthrough.TestSupport.FixedAIStrategy
      )

    {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

    assert has_element?(view, "#player-side-value[data-side='white']")
    assert has_element?(view, "#black-seat-status", "Black: AI")
    refute has_element?(view, "#resign-game-button")

    view
    |> element("#square-a7")
    |> render_click()

    view
    |> element("#square-a6")
    |> render_click()

    assert has_element?(view, "#resign-game-button")
    assert has_element?(view, "#square-a7[data-last-move='false']")
    assert has_element?(view, "#square-a6[data-last-move='false']")
    assert has_element?(view, "#square-a2[data-last-move='true']")
    assert has_element?(view, "#square-a3[data-last-move='true']")
    assert has_element?(view, "#turn-value[data-turn='White']")
  end

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(fun, 1), do: fun.()

  defp assert_eventually(fun, attempts) do
    try do
      fun.()
    rescue
      _error in [ExUnit.AssertionError] ->
        Process.sleep(10)
        assert_eventually(fun, attempts - 1)
    end
  end

  defp create_game! do
    game_id = "game-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, ^game_id} = Breakthrough.Games.GameManager.create_game(id: game_id)
    game_id
  end
end
