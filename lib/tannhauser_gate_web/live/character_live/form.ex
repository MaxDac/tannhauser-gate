defmodule TannhauserGateWeb.CharacterLive.Form do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Storage, Stories}
  alias TannhauserGate.Characters.Character

  @impl true
  def mount(params, _session, socket) do
    stories = Stories.list_stories()

    socket =
      socket
      |> assign(:story_options, Enum.map(stories, &{&1.name, &1.id}))
      |> allow_upload(:avatar,
        accept: Storage.allowed_extensions(),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, apply_action(socket, socket.assigns.live_action, params, stories)}
  end

  defp apply_action(socket, :new, _params, stories) do
    default = Enum.find(stories, & &1.is_default) || List.first(stories)
    character = %Character{story_id: default && default.id}

    socket
    |> assign(:page_title, "New character")
    |> assign(:character, character)
    |> assign_form(Characters.change_character(character))
  end

  defp apply_action(socket, :edit, %{"id" => id}, _stories) do
    character = Characters.get_character!(id)

    if Characters.can_edit?(socket.assigns.current_user, character) do
      socket
      |> assign(:page_title, "Edit #{character.name}")
      |> assign(:character, character)
      |> assign_form(Characters.change_character(character))
    else
      socket
      |> put_flash(:error, "You can't edit this character.")
      |> push_navigate(to: ~p"/characters/#{character}")
    end
  end

  @impl true
  def handle_event("validate", %{"character" => params}, socket) do
    changeset = Characters.change_character(socket.assigns.character, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("save", %{"character" => params}, socket) do
    avatar_path =
      socket
      |> consume_uploaded_entries(:avatar, fn %{path: path}, entry ->
        {:ok, Storage.store_upload!(path, entry.client_name)}
      end)
      |> List.first()

    save(socket, socket.assigns.live_action, params, avatar_path)
  end

  defp save(socket, :new, params, avatar_path) do
    case Characters.create_character(socket.assigns.current_user, params, avatar_path) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character created")
         |> push_navigate(to: ~p"/characters/#{character}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params, avatar_path) do
    case Characters.update_character(socket.assigns.character, params, avatar_path) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character updated")
         |> push_navigate(to: ~p"/characters/#{character}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp upload_error(:too_large), do: "The image is too large (max 5 MB)"
  defp upload_error(:not_accepted), do: "Unsupported file type"
  defp upload_error(:too_many_files), do: "Only one image is allowed"
  defp upload_error(other), do: "Upload error: #{inspect(other)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.header>
        {@page_title}
        <:subtitle>Name, face and past. The rain will do the rest.</:subtitle>
      </.header>

      <div class="mt-6 max-w-2xl rounded-xl border border-mint/20 bg-ink/80 p-6">
        <.form for={@form} id="character-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label="Character name" required />
          <.input field={@form[:story_id]} type="select" label="Story" options={@story_options} />

          <div phx-drop-target={@uploads.avatar.ref} class="space-y-2">
            <label
              for={@uploads.avatar.ref}
              class="block text-xs font-semibold uppercase tracking-widest text-secondary"
            >
              Avatar (photo)
            </label>
            <div class="flex items-center gap-4">
              <.avatar
                :if={@character.id && @uploads.avatar.entries == []}
                character={@character}
                class="h-16 w-16 text-2xl"
              />
              <div :for={entry <- @uploads.avatar.entries} class="flex items-center gap-3">
                <.live_img_preview
                  entry={entry}
                  class="h-16 w-16 rounded-full object-cover ring-2 ring-phosphor"
                />
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="text-xs text-red-400 hover:underline"
                  aria-label="Remove image"
                >
                  Remove
                </button>
                <p :for={err <- upload_errors(@uploads.avatar, entry)} class="text-sm text-red-400">
                  {upload_error(err)}
                </p>
              </div>
              <.live_file_input
                upload={@uploads.avatar}
                class="file-input file-input-sm file-input-secondary w-full max-w-xs"
              />
            </div>
            <p :for={err <- upload_errors(@uploads.avatar)} class="text-sm text-red-400">
              {upload_error(err)}
            </p>
          </div>

          <.input field={@form[:description]} type="textarea" label="Description" rows="4" />
          <.input field={@form[:background]} type="textarea" label="Background" rows="10" />

          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button phx-disable-with="Saving...">Save character</.button>
            <.link
              navigate={if @character.id, do: ~p"/characters/#{@character}", else: ~p"/characters"}
              class="text-sm font-semibold text-fog-400 hover:text-mint"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
