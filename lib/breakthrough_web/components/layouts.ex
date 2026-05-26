defmodule BreakthroughWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BreakthroughWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :show_flash_group, :boolean,
    default: true,
    doc: "whether to render the global flash group"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="app-shell" class="min-h-screen">
      <header class="border-b border-white/10 bg-zinc-950/55 backdrop-blur">
        <div class="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
          <.link navigate={~p"/"} id="home-link" class="flex items-center gap-3 text-white">
            <div class="flex h-11 w-11 items-center justify-center rounded-lg border border-white/10 bg-white/8 shadow-[0_10px_30px_rgba(0,0,0,0.18)]">
              <span class="display-copy text-xl">B</span>
            </div>
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.24em] text-zinc-400">
                Live Strategy
              </p>
              <p class="display-copy text-xl">Breakthrough</p>
            </div>
          </.link>

          <div class="flex items-center gap-3 rounded-full border border-emerald-300/20 bg-emerald-300/8 px-4 py-2 text-sm text-emerald-100">
            <span class="h-2 w-2 rounded-full bg-emerald-300"></span>
            <span>Live matches</span>
          </div>
        </div>
      </header>

      <main class="px-4 py-8 sm:px-6 lg:px-8 lg:py-10">
        <div class="mx-auto max-w-7xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group :if={@show_flash_group} flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
