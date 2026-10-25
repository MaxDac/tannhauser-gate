defmodule TannhauserGateWeb.GdrLive.Home do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Boards, Guide, Sheet}

  @impl true
  def mount(_params, _session, socket) do
    %{current_story: story, current_user: user} = socket.assigns
    mine = socket.assigns.active_character
    boards? = Boards.enabled?(story)

    {:ok,
     socket
     |> assign(:page_title, story.name)
     |> assign(:mine, mine)
     |> assign(:boards?, boards?)
     |> assign(:seen_at, if(boards?, do: Boards.last_seen_at(user, story)))
     |> load_announcements()
     |> assign(:guide, Guide.list_sections(story))
     |> assign(:items, Sheet.items_by_kind(story))}
  end

  # Shows the announcements (boards module) and marks them as read: the
  # ones published after the previous visit are flagged as new.
  defp load_announcements(%{assigns: %{boards?: true}} = socket) do
    %{current_story: story, current_user: user} = socket.assigns

    socket =
      socket
      |> assign(:announcements, Boards.list_announcements(story))
      |> assign(:announcements_unread, 0)

    if connected?(socket), do: Boards.mark_announcements_read(user, story)
    socket
  end

  defp load_announcements(socket), do: assign(socket, :announcements, [])

  @impl true
  def handle_info({:boards, :announcement, _announcement}, socket),
    do: {:noreply, load_announcements(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp new?(_announcement, nil), do: true
  defp new?(announcement, seen_at), do: DateTime.after?(announcement.inserted_at, seen_at)

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
      my_characters={@my_characters}
      active_character={@active_character}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <.header>
        {@current_story.name}
        <:subtitle>{@current_story.summary}</:subtitle>

        <:actions>
          <.button :if={@mine} id="enter-gdr" navigate={~p"/g/#{@current_story}/characters/#{@mine}"}>
            {dgettext("player", "Your character:")} {@mine.name}
          </.button>

          <.button
            :if={!@mine}
            id="create-character"
            navigate={~p"/g/#{@current_story}/characters/new"}
          >
            <.icon name="hero-plus" class="size-4" /> {dgettext("player", "Create your character")}
          </.button>
        </:actions>
      </.header>

      <p
        :if={@current_story.status == "draft"}
        id="draft-notice"
        class="mt-4 rounded-md border border-warning/40 p-3 text-sm text-warning"
      >
        {dgettext("player", "This GDR is a draft and only visible to its admin and masters.")}
      </p>

      <section :if={@boards?} id="announcements" class="mt-8">
        <h2 class="flex items-center gap-2 text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          <.icon name="hero-megaphone" class="size-4" /> {dgettext("player", "Announcements")}
          <.link
            :if={MapSet.member?(@permissions, :can_manage_world)}
            id="announcements-manage"
            navigate={~p"/g/#{@current_story}/master/boards"}
            class="ml-auto text-xs font-semibold normal-case tracking-normal text-base-content/60 transition hover:text-primary"
          >
            <.icon name="hero-pencil-square-micro" class="size-3" /> {dgettext("player", "Manage")}
          </.link>
        </h2>

        <p
          :if={@announcements == []}
          id="announcements-empty"
          class="mt-2 text-sm text-base-content/60"
        >
          {dgettext("player", "No announcements from the masters.")}
        </p>

        <ul class="mt-3 space-y-3">
          <li
            :for={announcement <- @announcements}
            id={"announcement-#{announcement.id}"}
            class={[
              "group rounded-xl border bg-base-200/70 p-4 transition hover:-translate-y-0.5 hover:shadow-phosphor",
              if(announcement.pinned,
                do: "border-primary/50",
                else: "border-secondary/20 hover:border-primary/40"
              )
            ]}
          >
            <header class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <.icon
                :if={announcement.pinned}
                name="hero-bookmark-solid"
                class="size-4 self-center text-primary"
              />
              <h3 class="font-semibold text-primary">{announcement.title}</h3>

              <span
                :if={new?(announcement, @seen_at)}
                id={"announcement-#{announcement.id}-new"}
                class="badge badge-xs badge-accent"
              >
                {dgettext("player", "new")}
              </span>

              <span class="ml-auto text-xs text-base-content/50">
                {(announcement.user && announcement.user.username) ||
                  dgettext("player", "The masters")} · {Calendar.strftime(
                  announcement.inserted_at,
                  "%d/%m/%Y %H:%M"
                )}
              </span>
            </header>

            <.markdown
              id={"announcement-#{announcement.id}-body"}
              content={announcement.body}
              class="mt-2 text-sm"
            />
          </li>
        </ul>
      </section>

      <section :if={@guide != []} id="gdr-guide" class="mt-8">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("player", "Guide")}
        </h2>

        <p class="mt-1 text-sm text-base-content/70">
          {dgettext("player", "The world, its rules and customs.")}
          <.link
            id="gdr-guide-link"
            navigate={~p"/g/#{@current_story}/guide"}
            class="link link-primary"
          >
            {dgettext("player", "Read the guide")}
          </.link>
        </p>
        <.guide_toc id="gdr-guide-toc" story={@current_story} sections={@guide} />
      </section>

      <section :for={{kind, items} <- @items} :if={items != []} id={"home-#{kind}"} class="mt-8">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {Sheet.kind_label(kind)}
        </h2>

        <ul class="mt-2 grid gap-2 sm:grid-cols-2">
          <li :for={item <- items} class="rounded-md border border-secondary/20 bg-base-200/70 p-3">
            <p class="font-semibold text-primary">
              {item.name}
              <span class="text-xs text-base-content/50">{item.min_value}–{item.max_value}</span>
            </p>

            <p :if={item.description} class="text-sm text-base-content/70">{item.description}</p>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
