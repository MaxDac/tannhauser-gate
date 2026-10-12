defmodule TannhauserGateWeb.GdrLive.Home do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Guide, Sheet}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    mine = Characters.get_user_story_character(socket.assigns.current_user, story.id)

    {:ok,
     socket
     |> assign(:page_title, story.name)
     |> assign(:mine, mine)
     |> assign(:guide, Guide.list_sections(story))
     |> assign(:items, Sheet.items_by_kind(story))}
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
        {@current_story.name}
        <:subtitle>{@current_story.summary}</:subtitle>

        <:actions>
          <.button :if={@mine} id="enter-gdr" navigate={~p"/g/#{@current_story}/characters/#{@mine}"}>
            Your character: {@mine.name}
          </.button>

          <.button
            :if={!@mine}
            id="create-character"
            navigate={~p"/g/#{@current_story}/characters/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Create your character
          </.button>
        </:actions>
      </.header>

      <p
        :if={@current_story.status == "draft"}
        id="draft-notice"
        class="mt-4 rounded-md border border-warning/40 p-3 text-sm text-warning"
      >
        This GDR is a draft and only visible to its admin and masters.
      </p>

      <section :if={@guide != []} id="gdr-guide" class="mt-8">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Guide</h2>

        <p class="mt-1 text-sm text-base-content/70">
          The world, its rules and customs.
          <.link
            id="gdr-guide-link"
            navigate={~p"/g/#{@current_story}/guide"}
            class="link link-primary"
          >
            Read the guide
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
