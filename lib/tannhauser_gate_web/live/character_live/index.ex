defmodule TannhauserGateWeb.CharacterLive.Index do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Characters

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    characters = Characters.list_story_characters(story.id)
    mine = Characters.get_user_story_character(socket.assigns.current_user, story.id)

    {:ok,
     socket
     |> assign(:page_title, "Characters · #{story.name}")
     |> assign(:mine, mine)
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
    >
      <.header>
        Characters
        <:subtitle>Everyone who walks through {@current_story.name}.</:subtitle>

        <:actions>
          <.button
            :if={is_nil(@mine)}
            id="new-character"
            navigate={~p"/g/#{@current_story}/characters/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Create your character
          </.button>

          <.button
            :if={@mine}
            id="my-character"
            navigate={~p"/g/#{@current_story}/characters/#{@mine}"}
          >
            Your character
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
        <.link
          :for={{dom_id, character} <- @streams.characters}
          id={dom_id}
          navigate={~p"/g/#{@current_story}/characters/#{character}"}
          class="group flex items-center gap-4 rounded-xl border border-secondary/20 bg-base-200/80 p-4 transition hover:border-primary/60 hover:shadow-phosphor"
        >
          <.avatar character={character} class="h-16 w-16 text-2xl" />
          <div class="min-w-0">
            <p class="truncate text-lg font-bold text-base-content group-hover:text-primary">
              {character.name}
            </p>

            <p class="truncate text-xs uppercase tracking-wider text-secondary">
              {(character.job && character.job.name) || "No job"} · {character.user.username}
            </p>

            <p class="mt-1 line-clamp-2 text-sm text-base-content/60">{character.description}</p>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
