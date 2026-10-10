defmodule TannhauserGateWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TannhauserGateWeb, :html

  alias TannhauserGate.Accounts
  alias TannhauserGate.Stories.Themes

  defp home_path(nil), do: ~p"/gdrs"
  defp home_path(story), do: ~p"/g/#{story}"

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app layout.

  Signed-in users get the navigation drawer (a daisyUI drawer, open on large
  screens and toggled from the top bar on small ones). Anonymous visitors get
  a centred card for the authentication pages.

  ## Examples

      <Layouts.app flash={@flash} current_user={@current_user}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the signed-in user, if any"
  attr :current_path, :string, default: nil, doc: "the current path, to highlight the drawer"
  attr :current_story, :map, default: nil, doc: "the GDR being visited, if any"

  slot :inner_block, required: true

  def app(%{current_user: nil} = assigns) do
    ~H"""
    <main class="flex min-h-screen flex-col items-center justify-center px-4 py-12">
      <.link href={~p"/"} class="mb-10"><.brand size={56} /></.link>
      <div class="card w-full max-w-md border border-secondary/30 bg-base-200/80 shadow-phosphor backdrop-blur">
        <div class="card-body p-8">
          {render_slot(@inner_block)}
        </div>
      </div>
      <p class="mt-8 text-xs uppercase tracking-[0.3em] text-fog-500">
        Neo-Meridian · 2121
      </p>
    </main>
    <.flash_group flash={@flash} />
    """
  end

  def app(assigns) do
    ~H"""
    <div
      id="app-shell"
      data-theme={@current_story && @current_story.theme}
      style={@current_story && Themes.style(@current_story.theme_overrides)}
      class="drawer bg-base-100 text-base-content lg:drawer-open"
    >
      <input id="drawer-toggle" type="checkbox" class="drawer-toggle" aria-label="Toggle navigation" />

      <div class="drawer-content flex min-h-screen min-w-0 flex-col">
        <header class="navbar border-b border-secondary/20 bg-base-200/90 px-4 lg:hidden">
          <div class="flex-1">
            <.link navigate={home_path(@current_story)}><.brand size={32} /></.link>
          </div>
          <label
            for="drawer-toggle"
            class="btn btn-square btn-ghost btn-sm border-secondary/40 text-secondary"
            aria-label="Open navigation"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </label>
        </header>

        <main class="min-w-0 flex-1 px-4 py-8 sm:px-6 lg:px-10">
          <div class="mx-auto max-w-6xl">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>

      <div class="drawer-side z-40">
        <label for="drawer-toggle" aria-label="Close navigation" class="drawer-overlay"></label>
        <aside
          id="drawer"
          class="flex min-h-full w-64 flex-col gap-6 border-r border-secondary/20 bg-base-200/95 p-4"
        >
          <.link navigate={home_path(@current_story)}>
            <.brand size={36} />
          </.link>
          <p
            :if={@current_story}
            id="current-gdr-name"
            class="-mt-3 truncate px-1 text-xs font-bold uppercase tracking-[0.2em] text-secondary"
          >
            {@current_story.name}
          </p>

          <ul :if={is_nil(@current_story)} class="menu w-full gap-1 p-0" aria-label="Sections">
            <li>
              <.nav_link navigate={~p"/gdrs"} icon="hero-squares-2x2" current_path={@current_path}>
                GDRs
              </.nav_link>
            </li>
            <li :if={@current_user.gm}>
              <.nav_link
                navigate={~p"/gdrs/request"}
                icon="hero-sparkles"
                current_path={@current_path}
              >
                My GDR
              </.nav_link>
            </li>
          </ul>

          <ul :if={@current_story} class="menu w-full gap-1 p-0" aria-label="Sections">
            <li>
              <.nav_link
                navigate={~p"/g/#{@current_story}"}
                icon="hero-home"
                current_path={@current_path}
              >
                Home
              </.nav_link>
            </li>
            <li>
              <.nav_link
                navigate={~p"/g/#{@current_story}/characters"}
                icon="hero-identification"
                current_path={@current_path}
              >
                Characters
              </.nav_link>
            </li>
            <li>
              <.nav_link
                navigate={~p"/g/#{@current_story}/map"}
                icon="hero-map"
                current_path={@current_path}
              >
                Map
              </.nav_link>
            </li>
            <li>
              <.nav_link
                navigate={~p"/g/#{@current_story}/forum"}
                icon="hero-chat-bubble-left-right"
                current_path={@current_path}
              >
                Forum
              </.nav_link>
            </li>
            <li>
              <.nav_link
                navigate={~p"/g/#{@current_story}/bank"}
                icon="hero-banknotes"
                current_path={@current_path}
              >
                Bank
              </.nav_link>
            </li>
            <li>
              <.nav_link
                navigate={~p"/g/#{@current_story}/jobs"}
                icon="hero-briefcase"
                current_path={@current_path}
              >
                Jobs
              </.nav_link>
            </li>
            <li :if={Accounts.admin?(@current_user) or @current_user.id == @current_story.owner_id}>
              <.nav_link
                navigate={~p"/g/#{@current_story}/gm"}
                icon="hero-adjustments-horizontal"
                current_path={@current_path}
              >
                GM dashboard
              </.nav_link>
            </li>
            <li>
              <.nav_link
                navigate={~p"/gdrs"}
                icon="hero-arrow-uturn-left"
                current_path={@current_path}
              >
                All GDRs
              </.nav_link>
            </li>
            <li :if={Accounts.admin?(@current_user)}>
              <.nav_link navigate={~p"/admin"} icon="hero-shield-check" current_path={@current_path}>
                Admin
              </.nav_link>
            </li>
          </ul>

          <ul class="menu mt-auto w-full gap-1 border-t border-secondary/20 p-0 pt-4">
            <li class="menu-title min-w-0 px-3 normal-case">
              <span class="block truncate" title={@current_user.username}>{@current_user.username}</span>
            </li>
            <li>
              <.nav_link
                navigate={~p"/users/settings"}
                icon="hero-cog-6-tooth"
                current_path={@current_path}
              >
                Settings
              </.nav_link>
            </li>
            <li>
              <.link
                href={~p"/users/log_out"}
                method="delete"
                class="flex items-center gap-3 rounded-md px-3 py-2 text-sm font-semibold uppercase tracking-wider text-fog-300 hover:bg-mint/10 hover:text-mint"
              >
                <.icon name="hero-arrow-left-on-rectangle" class="size-5" /> Log out
              </.link>
            </li>
          </ul>
        </aside>
      </div>
    </div>
    <.flash_group flash={@flash} />
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
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
