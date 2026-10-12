defmodule TannhauserGateWeb.CharacterLive.Show do
  @moduledoc """
  A character sheet. Everyone sees the public sheet (avatar, name, description,
  background, off-game info); the owner and the masters see the full sheet
  (trait values, state, player notes). Masters also see their private notes,
  review the character and set its state.
  """
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
      {:ok, assign_character(socket, character)}
    end
  end

  defp assign_character(socket, character) do
    user = socket.assigns.current_user
    full? = Characters.can_view_full_sheet?(user, character)
    master? = Characters.can_view_master_notes?(user, character)

    socket
    |> assign(:page_title, character.name)
    |> assign(:character, character)
    |> assign(:full?, full?)
    |> assign(:reviewer?, master?)
    |> assign(:owner?, not character.is_npc and character.user_id == user.id)
    |> assign(:sheet, if(full?, do: Characters.sheet(character), else: %{}))
    |> assign(:can_edit?, Characters.can_edit?(user, character))
    |> assign(
      :states,
      if(master?, do: Characters.list_states(socket.assigns.current_story), else: [])
    )
    |> assign(:review_form, to_form(%{"notes" => ""}, as: :review))
    |> assign(:state_form, to_form(%{"state_id" => character.state_id}, as: :character_state))
  end

  defp reload(socket) do
    assign_character(socket, Characters.get_character!(socket.assigns.character.id))
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

  def handle_event("submit_for_approval", _params, socket) do
    if socket.assigns.owner? do
      case Characters.submit_for_approval(socket.assigns.character) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, "Sent to the masters for approval") |> reload()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Characters.approval_error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can submit the character.")}
    end
  end

  def handle_event("review", %{"decision" => decision, "review" => %{"notes" => notes}}, socket) do
    %{character: character, current_user: user} = socket.assigns

    result =
      case decision do
        "approve" -> Characters.approve_character(character, user, notes)
        "reject" -> Characters.reject_character(character, user, notes)
        _ -> {:error, :invalid_status}
      end

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character #{Characters.approval_label(updated.approval_status)}")
         |> reload()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Characters.approval_error_message(reason))
         |> assign(:review_form, to_form(%{"notes" => notes}, as: :review))}
    end
  end

  def handle_event("set_state", %{"character_state" => %{"state_id" => state_id}}, socket) do
    if socket.assigns.reviewer? do
      case Characters.set_state(socket.assigns.character, state_id) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, "State updated") |> reload()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Characters.approval_error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the GDR masters can change the state.")}
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
      story_role={@story_role}
    >
      <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
        <.link
          navigate={~p"/g/#{@current_story}/characters"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Back to characters
        </.link>

        <div :if={@can_edit?} class="flex gap-2">
          <.button
            :if={@owner? and @character.approval_status in ["draft", "rejected"]}
            id="submit-for-approval"
            phx-click="submit_for_approval"
            class="btn btn-primary console-action"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Submit for approval
          </.button>
          <.button
            id="edit-character"
            navigate={~p"/g/#{@current_story}/characters/#{@character}/edit"}
          >
            Edit
          </.button>
          <.button
            id="delete-character"
            phx-click="delete"
            data-confirm="Delete this character? Their messages will be deleted too."
            class="btn btn-error btn-outline console-action"
          >
            Delete
          </.button>
        </div>
      </div>

      <div
        :if={@full? and not @character.is_npc}
        id="character-approval"
        class={[
          "mx-auto mb-6 max-w-3xl rounded-xl border p-4 text-sm",
          approval_class(@character.approval_status)
        ]}
      >
        <p class="flex flex-wrap items-center gap-2 font-semibold">
          <.icon name={approval_icon(@character.approval_status)} class="size-4" />
          <span id="character-approval-status">{Characters.approval_label(@character.approval_status)}</span>
          <span :if={@character.state} id="character-state" class="badge badge-sm badge-soft">
            {@character.state.name}
          </span>
        </p>
        <p class="mt-1 text-base-content/70">{approval_hint(@character, @owner?)}</p>
        <p :if={@character.review_notes} id="character-review-notes" class="mt-2 whitespace-pre-line">
          <span class="font-semibold">
            Notes from {(@character.reviewed_by && @character.reviewed_by.username) || "the masters"}:
          </span>
          {@character.review_notes}
        </p>
      </div>

      <section
        :if={@reviewer?}
        id="master-panel"
        class="mx-auto mb-6 grid max-w-3xl gap-4 rounded-xl border border-secondary/30 bg-base-200/80 p-4 sm:grid-cols-2"
      >
        <div :if={not @character.is_npc}>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Review</h2>
          <.form for={@review_form} id="review-form" phx-submit="review">
            <.input
              field={@review_form[:notes]}
              type="textarea"
              rows="3"
              label="Notes for the player (required to reject)"
            />
            <div class="flex gap-2">
              <.button
                :if={@character.approval_status != "approved"}
                id="approve-character"
                name="decision"
                value="approve"
                class="btn btn-success btn-sm console-action"
              >
                Approve
              </.button>
              <.button
                :if={@character.approval_status != "rejected"}
                id="reject-character"
                name="decision"
                value="reject"
                class="btn btn-error btn-outline btn-sm console-action"
              >
                Reject
              </.button>
            </div>
          </.form>
        </div>

        <div>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">State</h2>
          <.form for={@state_form} id="state-form" phx-submit="set_state">
            <.input
              field={@state_form[:state_id]}
              type="select"
              label="Character state"
              prompt="No state"
              options={Enum.map(@states, &{state_label(&1), &1.id})}
            />
            <.button class="btn btn-sm console-action">Set state</.button>
          </.form>
        </div>
      </section>

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
              <p class="notepad-label">
                Case file · {@character.story.name}
                <span :if={@character.is_npc} id="character-npc">· NPC</span>
              </p>

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

          <div :if={@character.off_game_info} id="character-off-game" class="mt-8">
            <p class="notepad-label">Off-game info</p>
            <p class="notepad-text whitespace-pre-line">{@character.off_game_info}</p>
          </div>

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

          <div :if={@full? and @character.player_notes} id="character-player-notes" class="mt-8">
            <p class="notepad-label">Player notes (private)</p>
            <p class="notepad-text whitespace-pre-line">{@character.player_notes}</p>
          </div>

          <div :if={@reviewer? and @character.master_notes} id="character-master-notes" class="mt-8">
            <p class="notepad-label">Master notes (hidden from the player)</p>
            <p class="notepad-text whitespace-pre-line">{@character.master_notes}</p>
          </div>

          <p class="notepad-stamp">
            {if @character.is_npc,
              do: "Non-player character",
              else: "Filed by #{TannhauserGate.Accounts.User.handle(@character.user)}"}
          </p>
        </div>
      </article>
    </Layouts.app>
    """
  end

  defp state_label(state),
    do: if(state.can_play, do: state.name, else: "#{state.name} (cannot play)")

  defp approval_class("approved"), do: "border-success/40 bg-success/10"
  defp approval_class("rejected"), do: "border-error/40 bg-error/10"
  defp approval_class("submitted"), do: "border-info/40 bg-info/10"
  defp approval_class(_), do: "border-warning/40 bg-warning/10"

  defp approval_icon("approved"), do: "hero-check-badge"
  defp approval_icon("rejected"), do: "hero-x-circle"
  defp approval_icon("submitted"), do: "hero-clock"
  defp approval_icon(_), do: "hero-pencil-square"

  defp approval_hint(character, owner?) do
    cond do
      character.approval_status == "approved" and not Characters.can_play?(character) ->
        "Approved, but the current state does not allow playing."

      character.approval_status == "approved" ->
        "Approved: this character can play."

      character.approval_status == "submitted" ->
        "Waiting for a master to review it. Until then it cannot speak in the chat rooms."

      character.approval_status == "rejected" and owner? ->
        "Rejected: edit it following the notes below and submit it again."

      character.approval_status == "rejected" ->
        "Rejected: the player can edit it and submit it again."

      owner? ->
        "Draft: you can use every feature except playing. Submit it when ready."

      true ->
        "Draft: not submitted yet."
    end
  end
end
