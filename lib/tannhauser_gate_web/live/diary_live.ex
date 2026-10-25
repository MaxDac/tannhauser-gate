defmodule TannhauserGateWeb.DiaryLive do
  @moduledoc """
  The in-character diary of a character (diary module). Everyone reads the
  public entries; the owner and the masters read them all (private ones for
  moderation, see `TannhauserGate.Diary`). The owner (the masters for NPCs)
  writes, edits and deletes entries; the masters delete any entry.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Calendars, Characters, Diary}
  alias TannhauserGate.Diary.Entry

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :diary}}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    story = socket.assigns.current_story

    case Characters.get_character(id) do
      %{story_id: story_id} = character when story_id == story.id ->
        user = socket.assigns.current_user

        {:ok,
         socket
         |> assign(:page_title, "Diary · #{character.name}")
         |> assign(:character, character)
         |> assign(:writer?, Diary.can_write?(user, character))
         |> assign(:deleter?, Diary.can_delete?(user, character))
         |> assign(:read_all?, Diary.can_read_all?(user, character))
         |> assign(:editing, nil)
         |> stream_configure(:entries, dom_id: &"diary-entry-#{&1.id}")
         |> stream(:entries, Diary.list_entries(character, user))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That character does not exist in this GDR.")
         |> push_navigate(to: ~p"/g/#{story}/characters")}
    end
  end

  @impl true
  def handle_event("new_entry", _params, socket) do
    if socket.assigns.writer? do
      label = Calendars.current_label(socket.assigns.current_story)
      {:noreply, open_editor(socket, %Entry{game_date_label: label})}
    else
      {:noreply, put_flash(socket, :error, Diary.error_message(:unauthorized))}
    end
  end

  def handle_event("edit_entry", %{"id" => id}, socket) do
    with true <- socket.assigns.writer?,
         %Entry{} = entry <- Diary.get_entry(socket.assigns.character, id) do
      {:noreply, open_editor(socket, entry)}
    else
      _ -> {:noreply, put_flash(socket, :error, Diary.error_message(:not_found))}
    end
  end

  def handle_event("cancel_entry", _params, socket),
    do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("validate_entry", %{"entry" => params}, socket) do
    changeset =
      socket.assigns.editing
      |> Diary.change_entry(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save_entry", %{"entry" => params}, socket) do
    %{character: character, current_user: user, editing: entry} = socket.assigns

    result =
      case entry do
        %Entry{id: nil} -> Diary.create_entry(user, character, params)
        %Entry{} -> Diary.update_entry(user, character, entry, params)
        nil -> {:error, :not_found}
      end

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, if(entry.id, do: "Entry updated", else: "Entry written"))
         |> assign(:editing, nil)
         |> insert_entry(saved, is_nil(entry.id))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Diary.error_message(reason))}
    end
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    %{character: character, current_user: user} = socket.assigns

    with %Entry{} = entry <- Diary.get_entry(character, id),
         {:ok, _} <- Diary.delete_entry(user, character, entry) do
      {:noreply,
       socket
       |> put_flash(:info, "Entry deleted")
       |> stream_delete(:entries, entry)}
    else
      nil -> {:noreply, put_flash(socket, :error, Diary.error_message(:not_found))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Diary.error_message(reason))}
    end
  end

  defp insert_entry(socket, entry, true), do: stream_insert(socket, :entries, entry, at: 0)
  defp insert_entry(socket, entry, false), do: stream_insert(socket, :entries, entry)

  defp open_editor(socket, entry) do
    socket
    |> assign(:editing, entry)
    |> assign(:form, to_form(Diary.change_entry(entry)))
  end

  defp visibility_class("masters"), do: "border-warning/60 text-warning"
  defp visibility_class("private"), do: "border-error/60 text-error"
  defp visibility_class(_), do: "border-secondary/40 text-secondary"

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
      <div class="mb-6">
        <.link
          id="diary-back"
          navigate={~p"/g/#{@current_story}/characters/#{@character}"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Back to {@character.name}'s sheet
        </.link>
      </div>

      <.header>
        <span class="flex items-center gap-3">
          <.avatar character={@character} class="size-12 text-xl" />
          <span>Diary of {@character.name}</span>
        </span>
        <:subtitle>
          In-character pages.
          <span :if={@read_all?} id="diary-moderation-note">
            You see every entry; private ones are shown to the masters only for moderation.
          </span>
        </:subtitle>
        <:actions :if={@writer? and is_nil(@editing)}>
          <.button id="diary-new-entry" phx-click="new_entry">
            <.icon name="hero-pencil-square" class="size-4" /> New entry
          </.button>
        </:actions>
      </.header>

      <section
        :if={@editing}
        id="diary-editor"
        class="mx-auto mt-6 max-w-3xl rounded-xl border border-secondary/30 bg-base-200/80 p-5 shadow-lg transition"
      >
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @editing.id, do: "Edit entry", else: "New entry"}
        </h2>
        <.form
          for={@form}
          id="diary-form"
          phx-change="validate_entry"
          phx-submit="save_entry"
          class="mt-3"
        >
          <div class="grid gap-x-4 sm:grid-cols-[1fr_12rem]">
            <.input field={@form[:title]} type="text" label="Title" required maxlength="120" />
            <.input
              field={@form[:game_date_label]}
              type="text"
              label="In-game date (optional)"
              placeholder="e.g. 3rd night of rain"
              maxlength="80"
            />
          </div>
          <.input
            field={@form[:visibility]}
            type="select"
            label="Who can read it"
            options={Diary.visibility_options()}
          />
          <.input
            field={@form[:body]}
            type="textarea"
            label="Text (Markdown)"
            rows="12"
            required
          />
          <div class="flex gap-2">
            <.button phx-disable-with="Saving..." class="btn btn-primary console-action">
              Save
            </.button>
            <.button
              id="diary-cancel"
              type="button"
              phx-click="cancel_entry"
              class="btn btn-ghost console-action"
            >
              Cancel
            </.button>
          </div>
        </.form>
      </section>

      <article id="diary" class="notepad mx-auto mt-8 max-w-3xl">
        <div class="notepad-spirals" aria-hidden="true">
          <span :for={_ <- 1..14} class="spiral"></span>
        </div>

        <div class="notepad-page">
          <ol id="diary-entries" phx-update="stream" class="space-y-10">
            <li id="diary-empty" class="hidden only:block notepad-text opacity-60">
              The pages are still blank.
            </li>
            <li :for={{dom_id, entry} <- @streams.entries} id={dom_id} class="group">
              <header class="flex flex-wrap items-baseline gap-x-3">
                <h2 class="notepad-title text-2xl">{entry.title}</h2>
                <span
                  :if={entry.visibility != "public"}
                  id={"#{dom_id}-visibility"}
                  class={[
                    "rounded border px-1.5 text-[0.65rem] font-bold uppercase tracking-widest",
                    visibility_class(entry.visibility)
                  ]}
                >
                  {Diary.visibility_label(entry.visibility)}
                </span>
              </header>
              <p class="notepad-label">
                <span :if={entry.game_date_label}>{entry.game_date_label} ·</span>
                written {Calendar.strftime(entry.inserted_at, "%d/%m/%Y %H:%M")}
              </p>
              <.markdown id={"#{dom_id}-body"} content={entry.body} class="notepad-text mt-2" />
              <div
                :if={@writer? or @deleter?}
                class="mt-2 flex gap-3 text-xs opacity-60 transition group-hover:opacity-100"
              >
                <button
                  :if={@writer?}
                  id={"#{dom_id}-edit"}
                  type="button"
                  phx-click="edit_entry"
                  phx-value-id={entry.id}
                  class="underline decoration-dotted underline-offset-4 hover:text-[#1d6b40]"
                >
                  Edit
                </button>
                <button
                  :if={@deleter?}
                  id={"#{dom_id}-delete"}
                  type="button"
                  phx-click="delete_entry"
                  phx-value-id={entry.id}
                  data-confirm="Tear this page out of the diary?"
                  class="underline decoration-dotted underline-offset-4 hover:text-error"
                >
                  Delete
                </button>
              </div>
            </li>
          </ol>
        </div>
      </article>
    </Layouts.app>
    """
  end
end
