defmodule TannhauserGateWeb.CharacterLive.Index do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Characters
  alias TannhauserGateWeb.GdrPresence

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    characters = Characters.list_story_characters(story.id)
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Characters · #{story.name}")
     |> assign(:mine, socket.assigns.active_character)
     |> assign(:can_create?, Characters.can_create_character?(user, story))
     |> assign(:empty?, characters == [])
     |> stream(:characters, characters)}
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
      my_characters={@my_characters}
      active_character={@active_character}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <.header>
        Characters
        <:subtitle>Everyone who walks through {@current_story.name}.</:subtitle>

        <:actions>
          <.button
            :if={@can_create?}
            id="new-character"
            navigate={~p"/g/#{@current_story}/characters/new"}
          >
            <.icon name="hero-plus" class="size-4" />
            {if @mine, do: "Create another character", else: "Create your character"}
          </.button>

          <.button
            :if={@mine}
            id="my-character"
            navigate={~p"/g/#{@current_story}/characters/#{@mine}"}
          >
            {if length(@my_characters) > 1, do: "Playing as #{@mine.name}", else: "Your character"}
          </.button>
        </:actions>
      </.header>

      <p
        :if={@empty?}
        class="mt-10 rounded-lg border border-dashed border-secondary/30 p-8 text-center text-base-content/60"
      >
        Nobody has arrived yet. Create your character to be the first.
      </p>

      <div id="characters" phx-update="stream" class="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <article
          :for={{dom_id, character} <- @streams.characters}
          id={dom_id}
          class="group relative flex items-center gap-4 rounded-xl border border-secondary/20 bg-base-200/80 p-4 transition hover:border-primary/60 hover:shadow-phosphor focus-within:z-10"
        >
          <.link
            navigate={~p"/g/#{@current_story}/characters/#{character}"}
            aria-label={"#{character.name}'s sheet"}
            class="shrink-0 transition-transform hover:scale-105"
          >
            <.avatar character={character} class="h-16 w-16 text-2xl" />
          </.link>
          <div class="min-w-0">
            <div class="flex items-center gap-2 text-lg font-bold text-base-content">
              <.character_quick_links
                id={"#{dom_id}-links"}
                story={@current_story}
                character={character}
                location={GdrPresence.character_location(@online, character.id, @master?)}
                class="truncate hover:text-primary"
              />
              <span :if={character.is_npc} class="badge badge-xs badge-secondary">NPC</span>
              <span
                :if={!character.is_npc and character.approval_status != "approved"}
                class="badge badge-xs badge-warning badge-soft"
              >
                {Characters.approval_label(character.approval_status)}
              </span>
            </div>

            <p class="truncate text-xs uppercase tracking-wider text-secondary">
              {(character.job && character.job.name) || "No job"} · {if character.is_npc,
                do: "NPC",
                else: character.user.username}
            </p>

            <.markdown
              :if={character.description}
              content={character.description}
              class="mt-1 line-clamp-2 text-sm text-base-content/60"
            />
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
