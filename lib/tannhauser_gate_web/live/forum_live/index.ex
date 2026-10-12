defmodule TannhauserGateWeb.ForumLive.Index do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Forum

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "Forum")
     |> assign(:sections, Forum.list_visible_sections(user, story))}
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
        Forum
        <:subtitle>Out of the rain: talk, plan and gossip.</:subtitle>
      </.header>

      <p :if={@sections == []} class="mt-8 text-base-content/60">No sections yet.</p>

      <ul id="forum-sections" class="mt-8 space-y-3">
        <li :for={%{section: section} = entry <- @sections} id={"forum-section-#{section.id}"}>
          <.link
            navigate={~p"/g/#{@current_story}/forum/sections/#{section}"}
            class={[
              "group flex items-center justify-between gap-4 rounded-xl border bg-base-200/80 p-4 transition hover:-translate-y-0.5 hover:border-primary/60 hover:shadow-phosphor",
              if(entry.unread_count > 0, do: "border-secondary/50", else: "border-secondary/20")
            ]}
          >
            <div class="min-w-0">
              <p class="flex flex-wrap items-center gap-2 text-lg font-bold group-hover:text-primary">
                {section.name}
                <.section_badges section={section} />
              </p>
              <p class="text-sm text-base-content/60">{section.description}</p>
            </div>
            <div class="flex shrink-0 flex-col items-end gap-1">
              <span class="text-xs uppercase tracking-wider text-secondary">
                {entry.topic_count} {if entry.topic_count == 1, do: "topic", else: "topics"}
              </span>
              <span
                :if={entry.unread_count > 0}
                id={"section-unread-#{section.id}"}
                class="badge badge-sm badge-secondary"
              >
                {entry.unread_count} new
              </span>
            </div>
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  attr :section, :map, required: true

  @doc false
  def section_badges(assigns) do
    ~H"""
    <span
      :if={@section.on_game}
      class="badge badge-xs badge-primary badge-soft"
      title="Written in character"
    >
      On game
    </span>
    <span :if={!@section.on_game} class="badge badge-xs badge-ghost" title="Written as the player">
      Off game
    </span>
    <span :if={@section.visibility != "all"} class="badge badge-xs badge-warning badge-soft">
      <.icon name="hero-lock-closed-mini" class="size-3" />
      {Forum.visibility_label(@section.visibility)}
    </span>
    """
  end
end
