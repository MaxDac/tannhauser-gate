defmodule TannhauserGateWeb.RoomLive do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Chat, Stories}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    location = Stories.get_location!(id)
    story = socket.assigns.current_story

    if location.story_id != story.id do
      {:ok,
       socket
       |> put_flash(:error, "That room does not exist in this GDR.")
       |> push_navigate(to: ~p"/g/#{story}/map")}
    else
      {:ok, load(socket, location)}
    end
  end

  defp load(socket, location) do
    %{current_user: user, current_story: story} = socket.assigns
    characters = Characters.playable_characters(user, story)
    own = Characters.get_user_story_character(user, story.id)

    if connected?(socket), do: Chat.subscribe(location.id)

    socket
    |> assign(:page_title, location.name)
    |> assign(:location, location)
    |> assign(:characters, characters)
    |> assign(:own_character, own)
    |> assign(:form_id, 0)
    |> assign(:form, new_form(characters))
    |> stream(:messages, Chat.list_messages(location.id))
  end

  defp new_form(characters, character_id \\ nil) do
    character_id = character_id || (List.first(characters) || %{id: nil}).id
    to_form(%{"character_id" => character_id, "body" => ""}, as: "message")
  end

  @impl true
  def handle_event("send", %{"message" => params}, socket) do
    %{current_user: user, location: location} = socket.assigns

    case Chat.create_message(user, location, params) do
      {:ok, _message} ->
        # The new message arrives through PubSub; reset the form by giving it
        # a new id while keeping the selected character.
        {:noreply,
         socket
         |> update(:form_id, &(&1 + 1))
         |> assign(:form, new_form(socket.assigns.characters, params["character_id"]))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(params, as: "message", errors: changeset_errors(changeset))
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Chat.error_message(reason))}
    end
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    story = socket.assigns.current_story

    with true <- socket.assigns.master?,
         %{} = message <- Chat.get_story_message(story.id, id) do
      {:ok, _} = Chat.delete_message(message)
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Only the GDR masters can delete messages.")}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  def handle_info({:deleted_message, message}, socket) do
    {:noreply, stream_delete(socket, :messages, message)}
  end

  defp speaker_label(%{is_npc: true, name: name}), do: "#{name} (NPC)"
  defp speaker_label(%{name: name}), do: name

  defp changeset_errors(changeset) do
    Enum.map(changeset.errors, fn {field, error} -> {field, error} end)
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
    >
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/map"}
          class="text-sm font-semibold text-mint hover:text-phosphor"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Back to the map
        </.link>
      </div>

      <.header>
        <span class="phosphor-text">{@location.name}</span>
        <:subtitle>{@location.description}</:subtitle>
      </.header>

      <section class="mt-6 flex h-[65vh] flex-col overflow-hidden rounded-xl border border-mint/30 bg-ink/80">
        <ol
          id="messages"
          phx-update="stream"
          phx-hook=".ScrollBottom"
          class="flex-1 space-y-4 overflow-y-auto p-4"
        >
          <li class="hidden only:block py-10 text-center text-sm text-fog-500" id="messages-empty">
            The room is quiet. Only the rain is talking.
          </li>
          <li
            :for={{dom_id, message} <- @streams.messages}
            id={dom_id}
            class="chat-message flex gap-3"
          >
            <.avatar character={message.character} class="h-11 w-11 shrink-0 text-lg" />
            <div class="min-w-0 flex-1">
              <p class="flex flex-wrap items-baseline gap-x-3">
                <.link
                  navigate={~p"/g/#{@current_story}/characters/#{message.character}"}
                  class="chat-name font-bold text-phosphor hover:underline"
                >
                  {message.character.name}
                </.link>
                <time class="text-xs text-fog-500" datetime={DateTime.to_iso8601(message.inserted_at)}>
                  {format_time(message.inserted_at)}
                </time>
                <button
                  :if={@master?}
                  type="button"
                  id={"delete-message-#{message.id}"}
                  phx-click="delete_message"
                  phx-value-id={message.id}
                  data-confirm="Delete this message?"
                  class="console-link-action text-xs text-error/70 hover:text-error"
                  aria-label="Delete message"
                >
                  <.icon name="hero-trash" class="size-3" />
                </button>
              </p>
              <p class="chat-body whitespace-pre-line break-words text-fog-200">{message.body}</p>
            </div>
          </li>
        </ol>

        <div class="border-t border-mint/20 bg-night/60 p-4">
          <p :if={@characters == [] and is_nil(@own_character)} class="text-sm text-fog-400">
            You need a character in this GDR to speak. <.link
              navigate={~p"/g/#{@current_story}/characters/new"}
              class="font-semibold text-mint hover:underline"
            >Create one</.link>.
          </p>
          <p
            :if={@own_character && !Characters.can_play?(@own_character)}
            id="cannot-play-notice"
            class="mb-3 text-sm text-fog-400"
          >
            {@own_character.name} cannot speak yet: a master must approve it and its state
            must allow playing. <.link
              navigate={~p"/g/#{@current_story}/characters/#{@own_character}"}
              class="font-semibold text-mint hover:underline"
            >Open the sheet</.link>.
          </p>
          <.form
            :if={@characters != []}
            for={@form}
            id={"message-form-#{@form_id}"}
            phx-submit="send"
            class="flex flex-col gap-3 sm:flex-row sm:items-end"
          >
            <div class="sm:w-56">
              <.input
                field={@form[:character_id]}
                type="select"
                label="Speak as"
                options={Enum.map(@characters, &{speaker_label(&1), &1.id})}
              />
            </div>
            <div class="flex-1">
              <.input
                field={@form[:body]}
                type="textarea"
                label="Message"
                rows="2"
                placeholder="Say something..."
                required
              />
            </div>
            <.button
              phx-disable-with="Sending..."
              class="btn btn-primary console-action sm:mb-[1.125rem]"
            >
              Send
            </.button>
          </.form>
        </div>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollBottom">
        // Keeps the chat scrolled to the newest message unless the reader scrolled up.
        export default {
          mounted() {
            this.el.scrollTop = this.el.scrollHeight
            this.observer = new MutationObserver(() => {
              const nearBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 200
              if (nearBottom || this.pending) this.el.scrollTop = this.el.scrollHeight
              this.pending = false
            })
            this.observer.observe(this.el, {childList: true})
            this.el.closest("section")?.addEventListener("submit", () => (this.pending = true))
          },
          destroyed() {
            this.observer && this.observer.disconnect()
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
