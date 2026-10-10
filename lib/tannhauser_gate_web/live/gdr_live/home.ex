defmodule TannhauserGateWeb.GdrLive.Home do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Sheet}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    mine = Characters.get_user_story_character(socket.assigns.current_user, story.id)

    {:ok,
     socket
     |> assign(:page_title, story.name)
     |> assign(:mine, mine)
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
        This GDR is a draft and only visible to its game master.
      </p>

      <section :if={present?(@current_story.world_background)} id="gdr-background" class="mt-8">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Background</h2>

        <p class="mt-2 whitespace-pre-line text-base-content/80">
          {@current_story.world_background}
        </p>
      </section>

      <section :if={present?(@current_story.rules)} id="gdr-rules" class="mt-8">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Rules</h2>

        <p class="mt-2 whitespace-pre-line text-base-content/80">{@current_story.rules}</p>
      </section>

      <section :if={present?(@current_story.customs)} id="gdr-customs" class="mt-8">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Customs</h2>

        <p class="mt-2 whitespace-pre-line text-base-content/80">{@current_story.customs}</p>
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

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
