defmodule TannhauserGateWeb.MasterLive do
  @moduledoc """
  Master tools: the landing page for the narrators of a GDR (its masters, its
  GDR admin and platform admins). It gathers the moderation and narration entry
  points; the GDR configuration lives in `TannhauserGateWeb.GmLive`.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Repo, Stories}

  @impl true
  def mount(_params, _session, socket) do
    story = Repo.preload(socket.assigns.current_story, :owner)

    {:ok,
     socket
     |> assign(:page_title, "Master tools")
     |> assign(:owner, story.owner)
     |> assign(:queue_count, length(Characters.list_approval_queue(story.id)))
     |> stream(:masters, Stories.list_masters(story))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
      story_role={@story_role}
      online={@online}
      last_location={@last_location}
      mail_unread={@mail_unread}
    >
      <.header>
        Master tools
        <:subtitle>Narrate {@current_story.name}: run its scenes, characters and forum.</:subtitle>

        <:actions>
          <.button
            :if={@gdr_admin?}
            id="master-gm-dashboard-link"
            navigate={~p"/g/#{@current_story}/gm"}
          >
            <.icon name="hero-adjustments-horizontal" class="size-4" /> GM dashboard
          </.button>
        </:actions>
      </.header>

      <div id="master-entry-points" class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.entry_point
          id="master-characters"
          navigate={~p"/g/#{@current_story}/master/characters"}
          icon="hero-identification"
          title="Character dashboard"
        >
          Approve new characters, set their state and edit any sheet.
          <span id="master-approval-count" class="badge badge-sm badge-info badge-soft ml-1">
            {@queue_count} awaiting approval
          </span>
        </.entry_point>

        <.entry_point
          id="master-npcs"
          navigate={~p"/g/#{@current_story}/master/npcs/new"}
          icon="hero-user-plus"
          title="New NPC"
        >
          Create a non-player character to speak as in the chat rooms.
        </.entry_point>

        <.entry_point
          id="master-moderation"
          navigate={~p"/g/#{@current_story}/master/moderation"}
          icon="hero-shield-check"
          title="Moderation"
        >
          Review and delete the latest chat messages and forum posts.
        </.entry_point>

        <.entry_point
          id="master-chat-log"
          navigate={~p"/g/#{@current_story}/master/chat-log"}
          icon="hero-document-magnifying-glass"
          title="Chat log"
        >
          Read the history of every room, archived messages included, by room and date.
        </.entry_point>

        <.entry_point
          id="master-zones"
          navigate={~p"/g/#{@current_story}/master/zones"}
          icon="hero-globe-europe-africa"
          title="Zone events"
        >
          Post what happens in the zones; players see it in the zone's rooms.
        </.entry_point>

        <.entry_point
          id="master-actions"
          navigate={~p"/g/#{@current_story}/master/actions"}
          icon="hero-bolt"
          title="Periodic actions"
        >
          Set per-character difficulties, reset cooldowns and read the action log.
        </.entry_point>

        <.entry_point
          :if={Stories.module_enabled?(@current_story, :items)}
          id="master-items"
          navigate={~p"/g/#{@current_story}/master/items"}
          icon="hero-shopping-bag"
          title="Items"
        >
          Grant and remove items and read the item log.
        </.entry_point>

        <.entry_point
          :if={Stories.module_enabled?(@current_story, :guilds)}
          id="master-guilds"
          navigate={~p"/g/#{@current_story}/master/guilds"}
          icon="hero-flag"
          title="Guilds"
        >
          Create guilds and factions, their ranks and salaries.
        </.entry_point>

        <.entry_point
          id="master-map"
          navigate={~p"/g/#{@current_story}/map"}
          icon="hero-map"
          title="Map and rooms"
        >
          Enter the chat rooms to narrate scenes.
        </.entry_point>

        <.entry_point
          id="master-forum"
          navigate={~p"/g/#{@current_story}/forum"}
          icon="hero-chat-bubble-left-right"
          title="Forum"
        >
          Read every topic and delete posts that break the rules.
        </.entry_point>
      </div>

      <section id="master-team" class="mt-10 max-w-3xl">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">The team</h2>

        <p class="mt-2 text-sm text-base-content/70">
          GDR admin:
          <span id="master-team-admin" class="font-semibold text-primary">
            {(@owner && @owner.username) || "Platform"}
          </span>
        </p>

        <ul id="master-team-masters" phx-update="stream" class="mt-2 flex flex-wrap gap-2">
          <li id="master-team-empty" class="hidden text-sm text-base-content/60 only:block">
            No other masters yet.
          </li>

          <li
            :for={{dom_id, master} <- @streams.masters}
            id={dom_id}
            class="badge badge-secondary badge-soft"
          >
            {master.username}
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp entry_point(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="group flex flex-col gap-2 rounded-xl border border-secondary/20 bg-base-200/80 p-5 transition hover:-translate-y-0.5 hover:border-primary hover:shadow-phosphor"
    >
      <span class="flex items-center gap-2 font-bold uppercase tracking-wider text-primary">
        <.icon name={@icon} class="size-5" /> {@title}
      </span>
      <span class="text-sm text-base-content/70">{render_slot(@inner_block)}</span>
    </.link>
    """
  end
end
