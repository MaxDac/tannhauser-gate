defmodule TannhauserGateWeb.CharacterLive.Form do
  @moduledoc """
  Character creation and editing.

  Players create their character with a multi-step wizard: identity, one step
  per sheet category with items (enforcing the creation budgets configured by
  the GDR admin) and a final review. NPC creation (`:new_npc`) and edits are
  single-page; masters are never limited by the budgets, while owners can
  change trait values only until the character is approved (then they raise
  items by spending XP).
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Sheet, Storage}
  alias TannhauserGate.Characters.Character

  @impl true
  def mount(params, _session, socket) do
    story = socket.assigns.current_story

    socket =
      socket
      |> assign(:items, Sheet.items_by_kind(story))
      |> assign(:categories, Sheet.categories(story))
      |> assign(:wizard?, false)
      |> assign(:step, nil)
      |> assign(:steps, [])
      |> assign(:step_errors, [])
      |> assign(:traits_locked?, false)
      |> allow_upload(:avatar,
        accept: Storage.allowed_extensions(),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new_npc, _params) do
    story = socket.assigns.current_story
    character = %Character{story_id: story.id, is_npc: true}

    socket
    |> assign(:page_title, "New NPC")
    |> assign(:character, character)
    |> assign(:master_notes?, true)
    |> assign(:trait_values, default_traits(socket, %{}))
    |> assign_form(Characters.change_character(character, %{}, master?: true))
  end

  defp apply_action(socket, :new, _params) do
    story = socket.assigns.current_story

    case Characters.get_user_story_character(socket.assigns.current_user, story.id) do
      nil ->
        character = %Character{story_id: story.id}

        steps =
          ["identity"] ++
            Enum.filter(Sheet.kinds(), &(socket.assigns.items[&1] != [])) ++ ["review"]

        socket
        |> assign(:page_title, "New character")
        |> assign(:character, character)
        |> assign(:master_notes?, false)
        |> assign(:wizard?, true)
        |> assign(:steps, steps)
        |> assign(:step, "identity")
        |> assign(:trait_values, default_traits(socket, %{}))
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
        master? = Characters.can_view_master_notes?(socket.assigns.current_user, character)

        socket
        |> assign(:page_title, "Edit #{character.name}")
        |> assign(:character, character)
        |> assign(:master_notes?, master?)
        |> assign(
          :traits_locked?,
          not master? and not Characters.sheet_editable_by_owner?(character)
        )
        |> assign(:trait_values, default_traits(socket, values))
        |> assign_form(Characters.change_character(character, %{}, master?: master?))

      true ->
        socket
        |> put_flash(:error, "You can't edit this character.")
        |> push_navigate(to: ~p"/g/#{story}/characters/#{character}")
    end
  end

  # Current value of every sheet item as a string, keyed by item id. Missing
  # values get the category default (its starting value when budgeted).
  defp default_traits(socket, values) do
    %{items: items, categories: categories} = socket.assigns

    for {kind, list} <- items, item <- list, into: %{} do
      default = Sheet.default_value(item, categories[kind])
      {to_string(item.id), to_string(Map.get(values, item.id, default))}
    end
  end

  @impl true
  def handle_event("validate", %{"character" => params}, socket) do
    params = scope_params(params, socket)

    changeset =
      Characters.change_character(socket.assigns.character, params,
        master?: socket.assigns.master_notes?
      )

    {:noreply,
     socket
     |> assign(:trait_values, merge_traits(socket.assigns.trait_values, params))
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("back", _params, %{assigns: %{wizard?: true}} = socket) do
    index = Enum.find_index(socket.assigns.steps, &(&1 == socket.assigns.step))
    step = Enum.at(socket.assigns.steps, max(index - 1, 0))
    {:noreply, socket |> assign(:step, step) |> assign(:step_errors, [])}
  end

  # Intermediate wizard steps: validate the step and move on.
  def handle_event(
        "save",
        %{"character" => params},
        %{assigns: %{wizard?: true, step: step}} = socket
      )
      when step != "review" do
    params = scope_params(params, socket)

    socket =
      assign(socket, :trait_values, merge_traits(socket.assigns.trait_values, params))

    case step_errors(socket, step, params) do
      {[], changeset} ->
        {:noreply, socket |> assign_form(changeset) |> assign(:step_errors, []) |> next_step()}

      {errors, changeset} ->
        {:noreply,
         socket
         |> assign_form(Map.put(changeset, :action, :validate))
         |> assign(:step_errors, errors)}
    end
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

  # Only values of existing sheet items are kept.
  defp merge_traits(values, %{"traits" => %{} = traits}),
    do: Map.merge(values, Map.take(traits, Map.keys(values)))

  defp merge_traits(values, _params), do: values

  defp next_step(socket) do
    index = Enum.find_index(socket.assigns.steps, &(&1 == socket.assigns.step))
    assign(socket, :step, Enum.at(socket.assigns.steps, index + 1))
  end

  defp step_errors(socket, "identity", params) do
    changeset =
      socket.assigns.character
      |> Characters.change_character(Map.delete(params, "traits"))
      |> Map.put(:action, :validate)

    {if(changeset.valid?, do: [], else: ["Fix the errors above to continue."]), changeset}
  end

  defp step_errors(socket, kind, params) do
    changeset =
      Characters.change_character(socket.assigns.character, Map.delete(params, "traits"))

    items = socket.assigns.items[kind]
    raw = socket.assigns.trait_values

    range_errors =
      for item <- items,
          message <- [range_error(item, raw[to_string(item.id)])],
          message != nil,
          do: message

    budget_errors =
      if range_errors == [] do
        socket.assigns.items
        |> Sheet.creation_errors(socket.assigns.categories, int_values(socket), [kind])
        |> Enum.map(&elem(&1, 1))
      else
        []
      end

    {range_errors ++ budget_errors, changeset}
  end

  defp range_error(item, raw) do
    case Integer.parse(String.trim(to_string(raw))) do
      {value, ""} when value >= item.min_value and value <= item.max_value ->
        nil

      {_, ""} ->
        "#{item.name} must be between #{item.min_value} and #{item.max_value}"

      _ ->
        "#{item.name} must be a whole number"
    end
  end

  # The current trait values as integers keyed by item id (invalid ones are
  # left out, so they fall back to the item minimum).
  defp int_values(socket) do
    for {id, raw} <- socket.assigns.trait_values,
        {int_id, ""} <- [Integer.parse(to_string(id))],
        {value, ""} <- [Integer.parse(String.trim(to_string(raw)))],
        into: %{},
        do: {int_id, value}
  end

  # The character always belongs to the GDR being visited.
  defp scope_params(params, socket) do
    params = Map.put(params, "story_id", socket.assigns.current_story.id)

    if socket.assigns.traits_locked?, do: Map.delete(params, "traits"), else: params
  end

  defp save(socket, :new, params, avatar_path) do
    story = socket.assigns.current_story
    params = Map.put(params, "traits", socket.assigns.trait_values)

    case Characters.create_character(socket.assigns.current_user, params, avatar_path) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character created as a draft: submit it for approval when ready.")
         |> push_navigate(to: ~p"/g/#{story}/characters/#{character}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign_form(changeset)
         |> assign(:step_errors, changeset_messages(changeset))}
    end
  end

  defp save(socket, :new_npc, params, avatar_path) do
    story = socket.assigns.current_story

    case Characters.create_npc(socket.assigns.current_user, story, params, avatar_path) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, "NPC created")
         |> push_navigate(to: ~p"/g/#{story}/characters/#{character}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Only the GDR masters can create NPCs.")}
    end
  end

  defp save(socket, :edit, params, avatar_path) do
    story = socket.assigns.current_story
    opts = [master?: socket.assigns.master_notes?]

    case Characters.update_character(socket.assigns.character, params, avatar_path, opts) do
      {:ok, character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character updated")
         |> push_navigate(to: ~p"/g/#{story}/characters/#{character}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp changeset_messages(changeset) do
    Enum.map(changeset.errors, fn
      {:traits, error} -> translate_error(error)
      {field, error} -> "#{Phoenix.Naming.humanize(field)} #{translate_error(error)}"
    end)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp upload_error(:too_large), do: "The image is too large (max 5 MB)"
  defp upload_error(:not_accepted), do: "Unsupported file type"
  defp upload_error(:too_many_files), do: "Only one image is allowed"
  defp upload_error(other), do: "Upload error: #{inspect(other)}"

  defp step_label("identity"), do: "Identity"
  defp step_label("review"), do: "Review"
  defp step_label(kind), do: Sheet.kind_label(kind)

  # Whether a section is visible: always in single-page forms, only on its
  # step in the wizard.
  defp shown?(%{wizard?: false}, _step), do: true
  defp shown?(%{step: step}, step), do: true
  defp shown?(_assigns, _step), do: false

  @impl true
  def render(assigns) do
    avatar_errors =
      upload_errors(assigns.uploads.avatar) ++
        Enum.flat_map(assigns.uploads.avatar.entries, &upload_errors(assigns.uploads.avatar, &1))

    values =
      for {id, raw} <- assigns.trait_values,
          {value, ""} <- [Integer.parse(String.trim(to_string(raw)))],
          into: %{},
          do: {String.to_integer(id), value}

    budgeted? = not assigns.master_notes? and not assigns.traits_locked?

    assigns =
      assigns
      |> assign(:avatar_errors, Enum.map(avatar_errors, &upload_error/1))
      |> assign(:trait_errors, Enum.map(assigns.form[:traits].errors, &translate_error/1))
      |> assign(:budgets, budgets(assigns, values, budgeted?))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
      story_role={@story_role}
    >
      <.header>
        {@page_title}
        <:subtitle :if={!@character.is_npc}>Who are you in {@current_story.name}?</:subtitle>
        <:subtitle :if={@character.is_npc}>
          A non-player character of {@current_story.name}, played by its masters.
        </:subtitle>
      </.header>

      <ol
        :if={@wizard?}
        id="wizard-steps"
        class="mt-6 flex max-w-2xl flex-wrap gap-2 text-xs font-bold uppercase tracking-wider"
        aria-label="Character creation steps"
      >
        <li
          :for={{step, index} <- Enum.with_index(@steps, 1)}
          id={"wizard-step-#{step}"}
          aria-current={if step == @step, do: "step"}
          class={[
            "flex items-center gap-2 rounded-full px-3 py-1 transition",
            if(step == @step,
              do: "bg-primary/20 text-primary ring-1 ring-primary/40",
              else: "bg-base-200/60 text-base-content/50"
            )
          ]}
        >
          <span class="tabular-nums">{index}</span> {step_label(step)}
        </li>
      </ol>

      <div class="mt-6 max-w-2xl rounded-xl border border-secondary/20 bg-base-200/80 p-6">
        <.form for={@form} id="character-form" phx-change="validate" phx-submit="save">
          <div id="identity-step" class={[!shown?(assigns, "identity") && "hidden"]}>
            <.input field={@form[:name]} type="text" label="Character name" required />
            <.error :for={msg <- Enum.map(@form[:story_id].errors, &translate_error/1)}>
              {msg}
            </.error>

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
            <.input
              field={@form[:off_game_info]}
              type="textarea"
              label="Off-game info (public)"
              rows="3"
            />
            <.input
              field={@form[:player_notes]}
              type="textarea"
              label="Player notes (only you and the masters)"
              rows="4"
            />
            <.input
              :if={@master_notes?}
              field={@form[:master_notes]}
              type="textarea"
              label="Master notes (hidden from the player)"
              rows="4"
            />
          </div>

          <p
            :if={@traits_locked?}
            id="traits-locked"
            class="mt-6 border-t border-secondary/20 pt-4 text-sm text-base-content/70"
          >
            The sheet of an approved character grows with experience: raise its attributes,
            skills and powers by spending XP from the character page.
          </p>

          <%= for {kind, items} <- @items, items != [], not @traits_locked? do %>
            <section
              :if={shown?(assigns, kind)}
              id={"sheet-#{kind}"}
              class={["border-secondary/20", !@wizard? && "mt-6 border-t pt-4"]}
            >
              <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
                {Sheet.kind_label(kind)}
              </h2>

              <.budget :if={@budgets[kind]} kind={kind} status={@budgets[kind]} />

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
            <%!-- Values of the other wizard steps travel with the form. --%>
            <input
              :for={item <- items}
              :if={!shown?(assigns, kind)}
              type="hidden"
              name={"character[traits][#{item.id}]"}
              value={@trait_values[to_string(item.id)]}
            />
          <% end %>

          <section :if={@wizard? and @step == "review"} id="review-step" class="space-y-4">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              Review {@form[:name].value}
            </h2>
            <p class="text-sm text-base-content/70">
              The character is saved as a draft: you can still change it, then submit it to the
              masters for approval from its page.
            </p>
            <div
              :for={{kind, items} <- @items}
              :if={items != []}
              id={"review-#{kind}"}
              class="rounded-lg border border-secondary/15 p-3"
            >
              <h3 class="text-xs font-bold uppercase tracking-wider text-secondary">
                {Sheet.kind_label(kind)}
              </h3>
              <dl class="mt-2 grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
                <div :for={item <- items} class="flex justify-between gap-2">
                  <dt class="text-base-content/70">{item.name}</dt>
                  <dd class="font-semibold tabular-nums">{@trait_values[to_string(item.id)]}</dd>
                </div>
              </dl>
            </div>
          </section>

          <div :if={@step_errors != []} id="step-errors" class="mt-4">
            <.error :for={msg <- @step_errors}>{msg}</.error>
          </div>
          <.error :for={msg <- @trait_errors}>{msg}</.error>

          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <div class="flex flex-wrap items-center gap-3">
              <.button
                :if={@wizard? and @step != "identity"}
                type="button"
                id="wizard-back"
                phx-click="back"
              >
                <.icon name="hero-arrow-left" class="size-4" /> Back
              </.button>
              <.button
                :if={@wizard? and @step != "review"}
                id="wizard-next"
                variant="primary"
                phx-disable-with="Checking..."
              >
                Next <.icon name="hero-arrow-right" class="size-4" />
              </.button>
              <.button
                :if={!@wizard? or @step == "review"}
                id="save-character"
                variant="primary"
                phx-disable-with="Saving..."
              >
                Save character
              </.button>
            </div>
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

  defp budgets(assigns, values, true) do
    for {kind, items} <- assigns.items, items != [], into: %{} do
      status = Sheet.budget_status(assigns.categories[kind], items, values)
      {kind, if(status.mode == "free", do: nil, else: status)}
    end
  end

  defp budgets(_assigns, _values, false), do: %{}

  attr :kind, :string, required: true
  attr :status, :map, required: true

  defp budget(%{status: %{mode: "points"}} = assigns) do
    ~H"""
    <p
      id={"budget-#{@kind}"}
      class={[
        "mt-2 rounded-md px-3 py-2 text-sm transition-colors",
        if(@status.ok?, do: "bg-success/10 text-success", else: "bg-error/10 text-error")
      ]}
    >
      <span class="font-semibold tabular-nums">{@status.remaining}</span>
      of {@status.total} points left to spend above the starting value.
    </p>
    """
  end

  defp budget(%{status: %{mode: "distribution"}} = assigns) do
    ~H"""
    <div
      id={"budget-#{@kind}"}
      class={[
        "mt-2 rounded-md px-3 py-2 text-sm transition-colors",
        if(@status.ok?, do: "bg-success/10 text-success", else: "bg-warning/10 text-warning")
      ]}
    >
      <p>
        Assign these values:
        <span class="font-semibold tabular-nums">{Enum.join(@status.distribution, ", ")}</span>
        <span class="text-base-content/60">(the other items keep the starting value).</span>
      </p>
      <p :if={@status.missing != []} class="mt-1 text-xs">
        Still to assign: <span class="tabular-nums">{Enum.join(@status.missing, ", ")}</span>
      </p>
    </div>
    """
  end
end
