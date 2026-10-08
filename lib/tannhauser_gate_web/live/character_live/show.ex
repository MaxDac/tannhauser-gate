defmodule TannhauserGateWeb.CharacterLive.Show do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Characters

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    character = Characters.get_character!(id)

    {:ok,
     socket
     |> assign(:page_title, character.name)
     |> assign(:character, character)
     |> assign(:can_edit?, Characters.can_edit?(socket.assigns.current_user, character))}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    if socket.assigns.can_edit? do
      {:ok, _} = Characters.delete_character(socket.assigns.character)

      {:noreply,
       socket
       |> put_flash(:info, "Character deleted")
       |> push_navigate(to: ~p"/characters")}
    else
      {:noreply, put_flash(socket, :error, "You can't delete this character.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
      <.link navigate={~p"/characters"} class="text-sm font-semibold text-mint hover:text-phosphor">
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" /> Back to characters
      </.link>
      <div :if={@can_edit?} class="flex gap-2">
        <.link navigate={~p"/characters/#{@character}/edit"}>
          <.button>Edit</.button>
        </.link>
        <.button
          phx-click="delete"
          data-confirm="Delete this character? Their messages will be deleted too."
          class="!border-red-400 !bg-red-500/10 hover:!bg-red-500/25 !text-red-300 !shadow-none"
        >
          Delete
        </.button>
      </div>
    </div>

    <article id="character-sheet" class="notepad mx-auto max-w-3xl">
      <div class="notepad-spirals" aria-hidden="true">
        <span :for={_ <- 1..14} class="spiral"></span>
      </div>
      <div class="notepad-page">
        <div class="flex flex-col gap-6 sm:flex-row">
          <figure class="polaroid shrink-0">
            <img
              :if={@character.avatar_path}
              src={@character.avatar_path}
              alt={"Photo of #{@character.name}"}
              class="h-44 w-40 object-cover"
            />
            <div
              :if={!@character.avatar_path}
              class="flex h-44 w-40 items-center justify-center bg-fog-300 text-6xl font-bold text-fog-500"
            >
              {String.first(@character.name)}
            </div>
            <figcaption>{@character.name}</figcaption>
          </figure>

          <div class="min-w-0 flex-1">
            <p class="notepad-label">Case file · {@character.story.name}</p>
            <h1 class="notepad-title">{@character.name}</h1>
            <p class="notepad-label mt-4">Description</p>
            <p class="notepad-text whitespace-pre-line">{@character.description || "—"}</p>
          </div>
        </div>

        <p class="notepad-label mt-8">Background</p>
        <p class="notepad-text whitespace-pre-line">{@character.background || "—"}</p>

        <p class="notepad-stamp">Filed by {TannhauserGate.Accounts.User.handle(@character.user)}</p>
      </div>
    </article>
    """
  end
end
