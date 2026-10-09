defmodule TannhauserGateWeb.CharacterLive.Form do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Sheet, Storage}
  alias TannhauserGate.Characters.Character

  @impl true
  def mount(params, _session, socket) do
    story = socket.assigns.current_story

    socket =
      socket
      |> assign(:items, Sheet.items_by_kind(story))
      |> allow_upload(:avatar,
        accept: Storage.allowed_extensions(),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    story = socket.assigns.current_story

    case Characters.get_user_story_character(socket.assigns.current_user, story.id) do
      nil ->
        character = %Character{story_id: story.id}

        socket
        |> assign(:page_title, "New character")
        |> assign(:character, character)
        |> assign(:trait_values, default_traits(socket.assigns.items, %{}))
        |> assign_form(Characters.change_character(character))

      existing ->
        socket
        |> put_flash(:info, "You already have a character in this GDR.")
        |> push_navigate(to: ~p"/g/#{story}/characters/#{existing}/edit")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    story = socket.assigns.current_story
    character = Characters.get_character!(id)

    cond do
      character.story_id != story.id ->
        socket
        |> put_flash(:error, "That character does not exist in this GDR.")
        |> push_navigate(to: ~p"/g/#{story}/characters")

      Characters.can_edit?(socket.assigns.current_user, character) ->
        values = Characters.trait_values(character)

        socket
        |> assign(:page_title, "Edit #{character.name}")
        |> assign(:character, character)
        |> assign(:trait_values, default_traits(socket.assigns.items, values))
        |> assign_form(Characters.change_character(character))

      true ->
        socket
        |> put_flash(:error, "You can't edit this character.")
        |> push_navigate(to: ~p"/g/#{story}/characters/#{character}")
    end
  end

  # Current value of every sheet item as a string, keyed by item id.
  defp default_traits(items, values) do
    for {_kind, list} <- items, item <- list, into: %{} do
      {to_string(item.id), to_string(Map.get(values, item.id, item.min_value))}
    end
  end

  @impl true
  def handle_event("validate", %{"character" => params}, socket) do
    params = scope_params(params, socket)
    changeset = Characters.change_character(socket.assigns.character, params)

    {:noreply,
     socket
     |> assign(:trait_values, Map.merge(socket.assigns.trait_values, params["traits"] || %{}))
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("save", %{"character" => params}, socket) do
    params = scope_params(params, socket)

    avatar_path =
      socket
      |> consume_uploaded_entries(:avatar, fn %{path: path}, entry ->
        {:ok, Storage.store_upload!(path, entry.client_name)}
      end)
      |> List.first()

    save(socket, socket.assigns.live_action, params, avatar_path)
  end

  # The character always belongs to the GDR being visited.
  defp scope_params(params, socket) do
    Map.put(params, "story_id", socket.assigns.current_story.id)
  end

  defp save(socket, :new, params, avatar_path) do
    story = socket.assigns.current_story

    case Characters.create_character(socket.assigns.current_user, params, avatar_path) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character created")
         |> push_navigate(to: ~p"/g/#{story}/characters/#{character}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(socket, :edit, params, avatar_path) do
    story = socket.assigns.current_story

    case Characters.update_character(socket.assigns.character, params, avatar_path) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character updated")
         |> push_navigate(to: ~p"/g/#{story}/characters/#{character}")}

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
    avatar_errors =
      upload_errors(assigns.uploads.avatar) ++
        Enum.flat_map(assigns.uploads.avatar.entries, &upload_errors(assigns.uploads.avatar, &1))

    assigns =
      assigns
      |> assign(:avatar_errors, Enum.map(avatar_errors, &upload_error/1))
      |> assign(:trait_errors, Enum.map(assigns.form[:traits].errors, &translate_error/1))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
    >
      <.header>
        {@page_title}
        <:subtitle>Who are you in {@current_story.name}?</:subtitle>
      </.header>

      <div class="mt-6 max-w-2xl rounded-xl border border-secondary/20 bg-base-200/80 p-6">
        <.form for={@form} id="character-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label="Character name" required />
          <.error :for={msg <- Enum.map(@form[:story_id].errors, &translate_error/1)}>{msg}</.error>

          <div phx-drop-target={@uploads.avatar.ref} class="space-y-2">
            <label for={@uploads.avatar.ref} class="console-label">
              Avatar (photo)
            </label>

            <div class="flex flex-wrap items-center gap-4">
              <.avatar
                :if={@character.id && @uploads.avatar.entries == []}
                character={@character}
                class="h-16 w-16 text-2xl"
              />
              <div :for={entry <- @uploads.avatar.entries} class="flex items-center gap-3">
                <.live_img_preview
                  entry={entry}
                  class="h-16 w-16 rounded-full object-cover ring-2 ring-primary"
                />
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="console-link-action text-xs text-error hover:underline"
                  aria-label="Remove image"
                >
                  Remove
                </button>
              </div>

              <.live_file_input
                upload={@uploads.avatar}
                class="file-input file-input-secondary console-field w-full max-w-xs"
                aria-invalid={if @avatar_errors != [], do: "true"}
                aria-describedby={
                  if(@avatar_errors != [], do: "avatar-hint avatar-errors", else: "avatar-hint")
                }
              />
            </div>

            <p id="avatar-hint" class="text-xs text-base-content/60">
              JPG, PNG, WebP or GIF. Maximum 5 MB.
            </p>

            <div :if={@avatar_errors != []} id="avatar-errors">
              <.error :for={error <- @avatar_errors}>{error}</.error>
            </div>
          </div>
          <.input field={@form[:description]} type="textarea" label="Description" rows="4" />
          <.input field={@form[:background]} type="textarea" label="Background" rows="10" />
          <section
            :for={{kind, items} <- @items}
            :if={items != []}
            id={"sheet-#{kind}"}
            class="mt-6 border-t border-secondary/20 pt-4"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {Sheet.kind_label(kind)}
            </h2>

            <div class="mt-3 grid gap-x-6 sm:grid-cols-2">
              <div :for={item <- items}>
                <.input
                  type="number"
                  id={"trait-#{item.id}"}
                  name={"character[traits][#{item.id}]"}
                  value={@trait_values[to_string(item.id)]}
                  label={"#{item.name} (#{item.min_value}–#{item.max_value})"}
                  min={item.min_value}
                  max={item.max_value}
                />
                <p :if={item.description} class="-mt-1 mb-2 text-xs text-base-content/60">
                  {item.description}
                </p>
              </div>
            </div>
          </section>

          <.error :for={msg <- @trait_errors}>{msg}</.error>

          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button phx-disable-with="Saving...">Save character</.button>
            <.link
              navigate={
                if @character.id,
                  do: ~p"/g/#{@current_story}/characters/#{@character}",
                  else: ~p"/g/#{@current_story}/characters"
              }
              class="console-link-action text-sm font-semibold text-base-content/60 hover:text-secondary"
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
