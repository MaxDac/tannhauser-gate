defmodule TannhauserGateWeb.CharacterLive.Index do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Characters

  @impl true
  def mount(_params, _session, socket) do
    characters = Characters.list_user_characters(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Characters")
     |> assign(:empty?, characters == [])
     |> stream(:characters, characters)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Your characters
      <:subtitle>Every soul in Neo-Meridian has a file. These are yours.</:subtitle>
      <:actions>
        <.link navigate={~p"/characters/new"}>
          <.button><.icon name="hero-plus" class="h-4 w-4" /> New character</.button>
        </.link>
      </:actions>
    </.header>

    <p
      :if={@empty?}
      class="mt-10 rounded-lg border border-dashed border-teal/30 p-8 text-center text-slate-400"
    >
      No characters yet. Create one to step into the rain.
    </p>

    <div id="characters" phx-update="stream" class="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      <.link
        :for={{dom_id, character} <- @streams.characters}
        id={dom_id}
        navigate={~p"/characters/#{character}"}
        class="group flex items-center gap-4 rounded-xl border border-teal/20 bg-ink/80 p-4 transition hover:border-neon/60 hover:shadow-neon"
      >
        <.avatar character={character} class="h-16 w-16 text-2xl" />
        <div class="min-w-0">
          <p class="truncate text-lg font-bold text-slate-100 group-hover:text-neon">
            {character.name}
          </p>
          <p class="truncate text-xs uppercase tracking-wider text-teal">{character.story.name}</p>
          <p class="mt-1 line-clamp-2 text-sm text-slate-400">{character.description}</p>
        </div>
      </.link>
    </div>
    """
  end
end
