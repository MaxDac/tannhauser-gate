defmodule TannhauserGateWeb.CharacterLive.Show do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Sheet}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    story = socket.assigns.current_story
    character = Characters.get_character!(id)

    if character.story_id != story.id do
      {:ok,
       socket
       |> put_flash(:error, "That character does not exist in this GDR.")
       |> push_navigate(to: ~p"/g/#{story}/characters")}
    else
      {:ok,
       socket
       |> assign(:page_title, character.name)
       |> assign(:character, character)
       |> assign(:sheet, Characters.sheet(character))
       |> assign(:can_edit?, Characters.can_edit?(socket.assigns.current_user, character))}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    if socket.assigns.can_edit? do
      {:ok, _} = Characters.delete_character(socket.assigns.character)

      {:noreply,
       socket
       |> put_flash(:info, "Character deleted")
       |> push_navigate(to: ~p"/g/#{socket.assigns.current_story}/characters")}
    else
      {:noreply, put_flash(socket, :error, "You can't delete this character.")}
    end
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
      <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
        <.link
          navigate={~p"/g/#{@current_story}/characters"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Back to characters
        </.link>

        <div :if={@can_edit?} class="flex gap-2">
          <.button navigate={~p"/g/#{@current_story}/characters/#{@character}/edit"}>Edit</.button>
          <.button
            phx-click="delete"
            data-confirm="Delete this character? Their messages will be deleted too."
            class="btn btn-error btn-outline console-action"
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

              <p class="notepad-label mt-4">Job</p>

              <p id="character-job" class="notepad-text">
                {(@character.job && @character.job.name) || "—"}
              </p>
            </div>
          </div>

          <p class="notepad-label mt-8">Background</p>

          <p class="notepad-text whitespace-pre-line">{@character.background || "—"}</p>

          <div :for={{kind, entries} <- @sheet} :if={entries != []} id={"sheet-#{kind}"} class="mt-8">
            <p class="notepad-label">{Sheet.kind_label(kind)}</p>

            <ul class="notepad-text">
              <li
                :for={{item, value} <- entries}
                class="flex justify-between gap-4"
                title={item.description}
              >
                <span>{item.name}</span>
                <span id={"trait-value-#{item.id}"} class="font-bold">{value}</span>
              </li>
            </ul>
          </div>

          <p class="notepad-stamp">Filed by {TannhauserGate.Accounts.User.handle(@character.user)}</p>
        </div>
      </article>
    </Layouts.app>
    """
  end
end
