defmodule TannhauserGateWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TannhauserGateWeb, :html

  alias TannhauserGate.{Accounts, Stories}
  alias TannhauserGate.Stories.Themes

  defp home_path(nil), do: ~p"/gdrs"
  defp home_path(story), do: ~p"/g/#{story}"

  defp room_path(story, location), do: ~p"/g/#{story}/rooms/#{location.id}"

  # The "Return to chat" link shows in a GDR with a remembered room, unless
  # the user is already there.
  defp return_to_chat?(%{current_story: story, last_location: %{} = location} = assigns)
       when not is_nil(story),
       do: assigns.current_path != room_path(story, location)

  defp return_to_chat?(_assigns), do: false

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

  attr :story_role, :atom,
    default: nil,
    doc: "the user's role in the GDR being visited (see `TannhauserGate.Stories.role/2`)"

  attr :online, :list,
    default: nil,
    doc: "the users online in the GDR (see `TannhauserGateWeb.GdrPresence`)"

  attr :mail_unread, :integer,
    default: 0,
    doc: "the unread messages of the GDR mailbox (see `TannhauserGateWeb.MailNotifier`)"

  attr :last_location, :map,
    default: nil,
    doc: "the user's last chat room in the GDR, for the \"Return to chat\" link"

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
          <.link
            :if={return_to_chat?(assigns)}
            id="header-return-to-chat"
            navigate={room_path(@current_story, @last_location)}
            class="btn btn-square btn-ghost btn-sm mr-2 border-secondary/40 text-mint"
            aria-label={"Return to chat: #{@last_location.name}"}
            title={"Return to chat: #{@last_location.name}"}
          >
            <.icon name="hero-chat-bubble-bottom-center-text" class="size-5" />
          </.link>
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
          <.link
            :if={return_to_chat?(assigns)}
            id="nav-return-to-chat"
            navigate={room_path(@current_story, @last_location)}
            class="group -mt-2 flex items-center gap-2 rounded-md border border-mint/40 bg-mint/10 px-3 py-2 text-xs font-semibold text-mint transition-all hover:border-mint hover:bg-mint/20 hover:shadow-[0_0_12px] hover:shadow-mint/30"
          >
            <.icon
              name="hero-chat-bubble-bottom-center-text"
              class="size-4 transition-transform group-hover:-translate-x-0.5"
            />
            <span class="min-w-0 flex-1">
              <span class="block uppercase tracking-[0.15em]">Return to chat</span>
              <span class="block truncate font-normal text-fog-400">{@last_location.name}</span>
            </span>
          </.link>

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
                id="nav-guide"
                navigate={~p"/g/#{@current_story}/guide"}
                icon="hero-book-open"
                current_path={@current_path}
              >
                Guide
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
                id="nav-mail"
                navigate={~p"/g/#{@current_story}/mail"}
                icon="hero-envelope"
                current_path={@current_path}
              >
                Mail
                <span
                  :if={@mail_unread > 0}
                  id="nav-mail-unread"
                  class="badge badge-sm badge-secondary ml-auto"
                  aria-label={"#{@mail_unread} unread"}
                >
                  {@mail_unread}
                </span>
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
            <li :if={Stories.module_enabled?(@current_story, :items)}>
              <.nav_link
                id="nav-market"
                navigate={~p"/g/#{@current_story}/market"}
                icon="hero-building-storefront"
                current_path={@current_path}
              >
                Market
              </.nav_link>
            </li>
            <li :if={Stories.module_enabled?(@current_story, :guilds)}>
              <.nav_link
                id="nav-guilds"
                navigate={~p"/g/#{@current_story}/guilds"}
                icon="hero-flag"
                current_path={@current_path}
              >
                Guilds
              </.nav_link>
            </li>
            <li :if={Stories.master_role?(@story_role)}>
              <.nav_link
                id="nav-master-tools"
                navigate={~p"/g/#{@current_story}/master"}
                icon="hero-megaphone"
                current_path={@current_path}
              >
                Master tools
              </.nav_link>
            </li>
            <li :if={Stories.admin_role?(@story_role)}>
              <.nav_link
                id="nav-gm-dashboard"
                navigate={~p"/g/#{@current_story}/gm"}
                icon="hero-adjustments-horizontal"
                current_path={@current_path}
              >
                GM dashboard
              </.nav_link>
            </li>
            <li :if={@current_story.community_url}>
              <a
                id="nav-community"
                href={@current_story.community_url}
                target="_blank"
                rel="noopener noreferrer"
                class="flex items-center gap-3 rounded-md text-sm"
              >
                <.icon name="hero-user-group" class="size-5" />
                <span class="flex-1 truncate">{@current_story.community_label || "Community"}</span>
                <.icon name="hero-arrow-top-right-on-square-micro" class="size-3 opacity-60" />
              </a>
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

          <section
            :if={@current_story && @online}
            id="online-users"
            class="border-t border-secondary/20 pt-4"
            aria-label="Online"
          >
            <h2 class="flex items-center gap-2 px-1 text-xs font-bold uppercase tracking-[0.2em] text-fog-400">
              <span class="size-2 rounded-full bg-mint shadow-[0_0_8px] shadow-mint/70"></span>
              Online <span class="text-fog-500">({length(@online)})</span>
            </h2>
            <.presence_status_form
              :if={TannhauserGateWeb.GdrPresence.user_status(@online, @current_user.id)}
              status={TannhauserGateWeb.GdrPresence.user_status(@online, @current_user.id)}
            />
            <ul class="mt-2 flex flex-col gap-1">
              <li
                :for={entry <- @online}
                id={"online-user-#{entry.user_id}"}
                class="rounded-md px-2 py-1 text-xs transition-colors hover:bg-mint/5"
              >
                <div
                  :if={entry[:character_id]}
                  class="flex min-w-0 items-baseline gap-1 font-semibold text-fog-200"
                >
                  <.presence_dot
                    id={"online-user-#{entry.user_id}-status"}
                    status={entry[:status] || "available"}
                  />
                  <.character_quick_links
                    id={"online-user-#{entry.user_id}-links"}
                    story={@current_story}
                    character={%{id: entry.character_id, name: entry.character_name}}
                    location={
                      TannhauserGateWeb.GdrPresence.character_location(
                        @online,
                        entry.character_id,
                        Stories.master_role?(@story_role)
                      )
                    }
                    status={entry[:status] || "available"}
                    class="hover:text-mint"
                  />
                  <span class="truncate font-normal text-fog-500">· {entry.username}</span>
                </div>
                <span
                  :if={!entry[:character_id]}
                  class="flex min-w-0 items-baseline gap-1 truncate font-semibold text-fog-200"
                >
                  <.presence_dot
                    id={"online-user-#{entry.user_id}-status"}
                    status={entry[:status] || "available"}
                  />
                  {entry.character_name || entry.username}
                  <span :if={entry.character_name} class="font-normal text-fog-500">
                    · {entry.username}
                  </span>
                </span>
                <span
                  :if={entry[:guilds] not in [nil, []]}
                  id={"online-user-#{entry.user_id}-guilds"}
                  class="block truncate text-fog-500"
                >
                  <.icon name="hero-flag-micro" class="size-3" /> {Enum.join(entry.guilds, ", ")}
                </span>
                <span :if={entry.location_name} class="block truncate text-fog-500">
                  <.icon name="hero-map-pin-micro" class="size-3" /> {entry.location_name}
                </span>
              </li>
            </ul>
          </section>

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

  # The selector of the current user's presence status in the GDR (handled
  # by `TannhauserGateWeb.GdrPresence`).
  attr :status, :string, required: true

  defp presence_status_form(assigns) do
    assigns =
      assign(assigns,
        form: to_form(%{"status" => assigns.status}, as: :presence),
        options:
          Enum.map(
            TannhauserGate.Stories.presence_statuses(),
            &{TannhauserGateWeb.CharacterComponents.presence_label(&1), &1}
          )
      )

    ~H"""
    <.form
      for={@form}
      id="presence-status-form"
      phx-change="set_presence_status"
      class="mt-2 flex items-center gap-2 px-1"
    >
      <.presence_dot id="presence-status-dot" status={@status} />
      <div class="min-w-0 flex-1 [&_.fieldset]:mb-0 [&_.fieldset]:p-0">
        <.input
          field={@form[:status]}
          id="presence-status"
          type="select"
          aria-label="Your status"
          options={@options}
          class="select select-xs w-full border-secondary/30 bg-ink/80 text-xs text-fog-200 transition-colors hover:border-mint/60 focus:border-mint"
        />
      </div>
    </.form>
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
