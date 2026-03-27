defmodule BreakthroughWeb.GameLiveTest do
  use BreakthroughWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the v1 board shell", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#game-shell")
    assert has_element?(view, "#breakthrough-board")
    assert has_element?(view, "#new-game-button")
    assert has_element?(view, "#square-a2[data-piece='B']")
    assert has_element?(view, "#square-a7[data-piece='W']")
    assert has_element?(view, "#selected-square-value[data-selected='none']")
  end

  test "selects a current turn piece", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#square-a7")
    |> render_click()

    assert has_element?(view, "#square-a7[data-selected='true']")
    assert has_element?(view, "#selected-square-value[data-selected='a7']")
    assert has_element?(view, "#legal-move-count[data-count='2']")
    assert has_element?(view, "#square-a6.ring-2")
    assert has_element?(view, "#square-b6.ring-2")
  end

  test "reset clears the current selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#square-a7")
    |> render_click()

    view
    |> element("#new-game-button")
    |> render_click()

    assert has_element?(view, "#square-a7[data-selected='false']")
    assert has_element?(view, "#selected-square-value[data-selected='none']")
  end

  test "selecting another current turn piece replaces the previous selection", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#square-a7")
    |> render_click()

    view
    |> element("#square-b7")
    |> render_click()

    assert has_element?(view, "#square-a7[data-selected='false']")
    assert has_element?(view, "#square-b7[data-selected='true']")
    assert has_element?(view, "#selected-square-value[data-selected='b7']")
    assert has_element?(view, "#square-a6[data-selected='false']")
    assert has_element?(view, "#square-a6.ring-2")
    assert has_element?(view, "#square-b6.ring-2")
    assert has_element?(view, "#square-c6.ring-2")
  end

  test "clicking a new current turn piece clears the previous move highlights", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#square-c7")
    |> render_click()

    assert has_element?(view, "#square-b6.ring-2")
    assert has_element?(view, "#square-c6.ring-2")
    assert has_element?(view, "#square-d6.ring-2")

    view
    |> element("#square-h7")
    |> render_click()

    refute has_element?(view, "#square-b6.ring-2")
    refute has_element?(view, "#square-c6.ring-2")
    refute has_element?(view, "#square-d6.ring-2")
    assert has_element?(view, "#square-g6.ring-2")
    assert has_element?(view, "#square-h6.ring-2")
  end
end
