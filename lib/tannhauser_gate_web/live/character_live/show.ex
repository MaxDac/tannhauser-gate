defmodule TannhauserGateWeb.CharacterLive.Show do
  @moduledoc """
  A character sheet. Everyone sees the public sheet (avatar, name, description,
  background, off-game info, public trackers); the owner and the masters see
  the full sheet (trait values, every tracker, XP, state, player notes).
  The owner of a playable character spends XP to raise items. Masters also see
  their private notes, review the character, set its state, edit its trackers
  and award XP.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{
    Characters,
    Diary,
    Experience,
    Guilds,
    Items,
    Origins,
    Quests,
    Sheet,
    Trackers
  }

  alias TannhauserGate.Items.Item

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    story = socket.assigns.current_story
    character = Characters.get_character!(id)

    if character.story_id != story.id do
      {:ok,
       socket
       |> put_flash(:error, dgettext("player", "That character does not exist in this GDR."))
       |> push_navigate(to: ~p"/g/#{story}/characters")}
    else
      {:ok,
       socket
       |> assign_character(character)
       |> allow_upload(:gallery,
         accept: Diary.image_extensions(),
         max_entries: 1,
         max_file_size: Diary.max_image_size()
       )
       |> assign(:gallery_form, to_form(%{"caption" => ""}, as: :gallery))}
    end
  end

  defp can?(socket, permission), do: MapSet.member?(socket.assigns.permissions, permission)

  defp assign_character(socket, character) do
    user = socket.assigns.current_user
    full? = Characters.can_view_full_sheet?(user, character)
    master? = Characters.can_view_master_notes?(user, character)

    socket
    |> assign(:page_title, character.name)
    |> assign(:character, character)
    |> assign(:full?, full?)
    |> assign(:reviewer?, master?)
    |> assign(:approver?, master? and can?(socket, :can_approve_characters))
    |> assign(:xp_awarder?, master? and can?(socket, :can_award_xp))
    |> assign(:owner?, not character.is_npc and character.user_id == user.id)
    |> assign(:sheet, if(full?, do: Characters.sheet(character), else: %{}))
    |> assign(:origins, Origins.character_origins(character))
    |> assign(:guilds, Guilds.character_guilds(character, user))
    |> assign(:quests, Quests.character_quests(character, user))
    |> assign(:bonuses, if(full?, do: bonuses(character), else: %{}))
    |> assign(:can_edit?, Characters.can_edit?(user, character))
    |> assign(
      :states,
      if(master?, do: Characters.list_states(socket.assigns.current_story), else: [])
    )
    |> assign_progress(character, full?, master?)
    |> assign_inventory(character, full?, master?)
    |> assign_diary(character)
    |> assign(:review_form, to_form(%{"notes" => ""}, as: :review))
    |> assign(:state_form, to_form(%{"state_id" => character.state_id}, as: :character_state))
  end

  defp assign_progress(socket, character, full?, master?) do
    owner? = not character.is_npc and character.user_id == socket.assigns.current_user.id
    can_spend? = owner? and Characters.can_play?(character)

    socket
    |> assign(:trackers, Trackers.character_trackers(character, public_only: not full?))
    |> assign(:xp, if(full?, do: Experience.totals(character)))
    |> assign(:xp_entries, if(full?, do: Experience.list_entries(character), else: []))
    |> assign(:can_spend?, can_spend?)
    |> assign(:costs, if(can_spend?, do: Experience.costs(character), else: %{}))
    |> assign(:award_form, to_form(%{"amount" => "", "reason" => ""}, as: :award))
    |> assign(:tracker_master?, master?)
  end

  # Origin bonuses plus the modifiers of the equipped items.
  defp bonuses(character) do
    [Origins.bonuses(character), Items.equipment_modifiers(character)]
    |> Origins.sum_bonuses()
    |> Map.reject(fn {_slug, n} -> n == 0 end)
  end

  # Owners and masters see the whole inventory; everyone else only the
  # equipped items. The owner of a playable character equips, uses and gives
  # items; masters equip and remove them.
  defp assign_inventory(socket, character, full?, master?) do
    inventory = Items.inventory(character)
    owner_play? = socket.assigns.owner? and Characters.can_play?(character)

    socket
    |> assign(:inventory, if(full?, do: inventory, else: Enum.filter(inventory, & &1.equipped)))
    |> assign(:items_on?, Items.enabled?(character.story))
    |> assign(:item_player?, owner_play?)
    |> assign(:item_master?, master? and can?(socket, :can_manage_economy))
    |> assign(:give_recipients, if(owner_play?, do: Items.give_recipients(character), else: []))
    |> assign(:give_form, to_form(%{"item_id" => "", "to" => "", "quantity" => "1"}, as: :give))
  end

  # Diary module: the latest readable entries and the gallery.
  defp assign_diary(socket, character) do
    user = socket.assigns.current_user
    diary? = Diary.enabled?(character.story)

    socket
    |> assign(:diary?, diary?)
    |> assign(:diary_entries, Diary.list_entries(character, user, limit: 3))
    |> assign(:diary_writer?, diary? and Diary.can_write?(user, character))
    |> assign(:gallery, Diary.list_images(character))
    |> assign(:gallery_manager?, diary? and Diary.can_manage_gallery?(user, character))
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
       |> put_flash(:info, dgettext("player", "Character deleted"))
       |> push_navigate(to: ~p"/g/#{socket.assigns.current_story}/characters")}
    else
      {:noreply,
       put_flash(socket, :error, dgettext("player", "You can't delete this character."))}
    end
  end

  def handle_event("validate_gallery", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_gallery_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :gallery, ref)}

  def handle_event("add_image", %{"gallery" => params}, socket) do
    %{character: character, current_user: user} = socket.assigns

    results =
      consume_uploaded_entries(socket, :gallery, fn %{path: path}, _entry ->
        {:ok, Diary.add_image(user, character, path, %{"caption" => params["caption"]})}
      end)

    case results do
      [{:ok, _image}] ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("player", "Picture added to the gallery"))
         |> assign(:gallery_form, to_form(%{"caption" => ""}, as: :gallery))
         |> reload()}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, Diary.error_message(reason))}

      [] ->
        {:noreply, put_flash(socket, :error, dgettext("player", "Choose a picture first."))}
    end
  end

  def handle_event("delete_image", %{"id" => id}, socket) do
    %{character: character, current_user: user} = socket.assigns

    case Diary.delete_image(user, character, id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, dgettext("player", "Picture removed")) |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Diary.error_message(reason))}
    end
  end

  def handle_event("submit_for_approval", _params, socket) do
    if socket.assigns.owner? do
      case Characters.submit_for_approval(socket.assigns.character) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("player", "Sent to the masters for approval"))
           |> reload()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Characters.approval_error_message(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("player", "Only the owner can submit the character."))}
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
         |> put_flash(
           :info,
           dgettext("player", "Character %{value}",
             value: Characters.approval_label(updated.approval_status)
           )
         )
         |> reload()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Characters.approval_error_message(reason))
         |> assign(:review_form, to_form(%{"notes" => notes}, as: :review))}
    end
  end

  def handle_event("set_state", %{"character_state" => %{"state_id" => state_id}}, socket) do
    if socket.assigns.approver? do
      case Characters.set_state(socket.assigns.character, state_id) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, dgettext("player", "State updated")) |> reload()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Characters.approval_error_message(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("player", "Only the GDR masters can change the state."))}
    end
  end

  def handle_event("raise", %{"item" => item_id}, socket) do
    %{character: character, current_user: user} = socket.assigns

    case Experience.spend(user, character, item_id) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("player", "%{item_name} raised to %{to_value} (%{amount} XP)",
             item_name: entry.item_name,
             to_value: entry.to_value,
             amount: entry.amount
           )
         )
         |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Experience.error_message(reason))}
    end
  end

  def handle_event("award_xp", %{"award" => params}, socket) do
    %{character: character, current_user: user} = socket.assigns

    case Experience.award(user, character, params["amount"], params["reason"]) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("player", "%{amount} XP recorded", amount: entry.amount))
         |> reload()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Experience.error_message(reason))
         |> assign(:award_form, to_form(params, as: :award))}
    end
  end

  def handle_event("set_tracker", %{"tracker_id" => id} = params, socket) do
    if socket.assigns.tracker_master? do
      character = socket.assigns.character
      tracker = Trackers.get_tracker!(socket.assigns.current_story, id)

      case set_tracker(character, tracker, params) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("player", "%{name} updated", name: tracker.name))
           |> reload()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Trackers.error_message(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("player", "Only the GDR masters can change trackers."))}
    end
  end

  def handle_event("equip_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_player? or socket.assigns.item_master?, fn c, u ->
      with {:ok, %{item: item}} <- Items.equip(c, item_id, u),
           do: {:ok, dgettext("player", "%{name} equipped", name: item.name)}
    end)
  end

  def handle_event("unequip_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_player? or socket.assigns.item_master?, fn c, u ->
      with {:ok, %{item: item}} <- Items.unequip(c, item_id, u),
           do: {:ok, dgettext("player", "%{name} unequipped", name: item.name)}
    end)
  end

  def handle_event("use_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_player?, fn c, u ->
      with {:ok, %{item: item, state: state}} <- Items.use_item(c, item_id, u),
           do:
             {:ok,
              dgettext("player", "%{name} used: %{name_2} %{value}/%{max}",
                name: item.name,
                name_2: state.tracker.name,
                value: state.value,
                max: state.max
              )}
    end)
  end

  def handle_event("remove_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_master?, fn c, u ->
      with {:ok, %{item: item}} <-
             Items.remove(c, item_id, 1, u, dgettext("player", "From the sheet")),
           do: {:ok, dgettext("player", "1× %{name} removed", name: item.name)}
    end)
  end

  def handle_event("give_item", %{"give" => params}, socket) do
    item_action(socket, socket.assigns.item_player?, fn c, u ->
      with {:ok, %{item: item, quantity: qty, to: to}} <-
             Items.give(c, params["to"], params["item_id"], params["quantity"], u),
           do:
             {:ok,
              dgettext("player", "Gave %{qty}× %{name} to %{name_2}",
                qty: qty,
                name: item.name,
                name_2: to.name
              )}
    end)
  end

  defp item_action(socket, allowed?, fun) do
    if allowed? do
      case fun.(socket.assigns.character, socket.assigns.current_user) do
        {:ok, message} -> {:noreply, socket |> put_flash(:info, message) |> reload()}
        {:error, reason} -> {:noreply, put_flash(socket, :error, Items.error_message(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("player", "You can't manage this character's items."))}
    end
  end

  # Applies a tracker form: `value` for simple trackers, `damage[type]` for
  # trackers with damage types.
  defp set_tracker(character, %{damage_types: []} = tracker, %{"value" => raw}) do
    with {value, ""} <- Integer.parse(String.trim(raw)),
         {:ok, _} <- Trackers.set(character, tracker, value) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_value}
    end
  end

  defp set_tracker(character, tracker, %{"damage" => damage}) when is_map(damage) do
    Enum.reduce_while(tracker.damage_types, :ok, fn type, :ok ->
      with {:ok, raw} <- Map.fetch(damage, type),
           {value, ""} <- Integer.parse(String.trim(raw)),
           {:ok, _} <- Trackers.set_damage(character, tracker, type, value) do
        {:cont, :ok}
      else
        :error -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
        _ -> {:halt, {:error, :invalid_value}}
      end
    end)
  end

  defp set_tracker(_character, _tracker, _params), do: {:error, :invalid_value}

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
      <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
        <.link
          navigate={~p"/g/#{@current_story}/characters"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> {dgettext(
            "player",
            "Back to characters"
          )}
        </.link>

        <div class="flex flex-wrap gap-2">
          <.button
            :if={
              not @owner? and not @character.is_npc and
                (@master? or @character.approval_status == "approved")
            }
            id="send-message"
            navigate={~p"/g/#{@current_story}/mail/new?to=#{@character.id}"}
          >
            <.icon name="hero-envelope" class="size-4" /> {dgettext("player", "Send message")}
          </.button>

          <.report_link
            :if={
              TannhauserGate.Reports.enabled?(@current_story) and
                @character.user_id != @current_user.id and
                (@master? or @character.approval_status == "approved")
            }
            id="report-character"
            story={@current_story}
            type="character"
            target_id={@character.id}
            return_to={~p"/g/#{@current_story}/characters/#{@character}"}
            label={dgettext("player", "Report")}
            class="btn btn-ghost console-action"
          />
          <div :if={@can_edit?} class="contents">
            <.button
              :if={@owner? and @character.approval_status in ["draft", "rejected"]}
              id="submit-for-approval"
              phx-click="submit_for_approval"
              class="btn btn-primary console-action"
            >
              <.icon name="hero-paper-airplane" class="size-4" /> {dgettext(
                "player",
                "Submit for approval"
              )}
            </.button>

            <.button
              id="edit-character"
              navigate={~p"/g/#{@current_story}/characters/#{@character}/edit"}
            >
              {dgettext("player", "Edit")}
            </.button>

            <.button
              id="delete-character"
              phx-click="delete"
              data-confirm={
                dgettext("player", "Delete this character? Their messages will be deleted too.")
              }
              class="btn btn-error btn-outline console-action"
            >
              {dgettext("player", "Delete")}
            </.button>
          </div>
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
            {dgettext("player", "Notes from")} {(@character.reviewed_by &&
                                                   @character.reviewed_by.username) ||
              dgettext("player", "the masters")}:
          </span>
          {@character.review_notes}
        </p>
      </div>

      <section
        :if={@approver? or @xp_awarder?}
        id="master-panel"
        class="mx-auto mb-6 grid max-w-3xl gap-4 rounded-xl border border-secondary/30 bg-base-200/80 p-4 sm:grid-cols-2"
      >
        <div :if={@approver? and not @character.is_npc}>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("player", "Review")}
          </h2>

          <.form for={@review_form} id="review-form" phx-submit="review">
            <.input
              field={@review_form[:notes]}
              type="textarea"
              rows="3"
              label={dgettext("player", "Notes for the player (required to reject)")}
            />
            <div class="flex gap-2">
              <.button
                :if={@character.approval_status != "approved"}
                id="approve-character"
                name="decision"
                value="approve"
                class="btn btn-success btn-sm console-action"
              >
                {dgettext("player", "Approve")}
              </.button>

              <.button
                :if={@character.approval_status != "rejected"}
                id="reject-character"
                name="decision"
                value="reject"
                class="btn btn-error btn-outline btn-sm console-action"
              >
                {dgettext("player", "Reject")}
              </.button>
            </div>
          </.form>
        </div>

        <div :if={@approver?}>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("player", "State")}
          </h2>

          <.form for={@state_form} id="state-form" phx-submit="set_state">
            <.input
              field={@state_form[:state_id]}
              type="select"
              label={dgettext("player", "Character state")}
              prompt={dgettext("player", "No state")}
              options={Enum.map(@states, &{state_label(&1), &1.id})}
            /> <.button class="btn btn-sm console-action">{dgettext("player", "Set state")}</.button>
          </.form>
        </div>

        <div :if={@xp_awarder?} class="sm:col-span-2">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("player", "Award XP")}
          </h2>

          <.form
            for={@award_form}
            id="xp-award-form"
            phx-submit="award_xp"
            class="grid gap-x-3 sm:grid-cols-[8rem_1fr_auto] sm:items-end"
          >
            <.input
              field={@award_form[:amount]}
              type="number"
              label={dgettext("player", "Amount (negative to correct)")}
              required
            />
            <.input
              field={@award_form[:reason]}
              type="text"
              label={dgettext("player", "Reason")}
              required
            />
            <.button class="btn btn-sm console-action mb-2">{dgettext("player", "Record")}</.button>
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
                alt={dgettext("player", "Photo of %{name}", name: @character.name)}
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
                {dgettext("player", "Case file ·")} {@character.story.name}
                <span :if={@character.is_npc} id="character-npc">{dgettext("player", "· NPC")}</span>
              </p>

              <h1 class="notepad-title">{@character.name}</h1>

              <p class="notepad-label mt-4">{dgettext("player", "Description")}</p>

              <.markdown
                id="character-description"
                content={@character.description || "—"}
                class="notepad-text"
              />
              <p class="notepad-label mt-4">{dgettext("player", "Job")}</p>

              <p id="character-job" class="notepad-text">
                {(@character.job && @character.job.name) || "—"}
              </p>
            </div>
          </div>

          <p class="notepad-label mt-8">{dgettext("player", "Background")}</p>

          <.markdown
            id="character-background"
            content={@character.background || "—"}
            class="notepad-text"
          />
          <div :if={@origins != []} id="character-origins" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Origins")}</p>

            <div class="mt-2 space-y-4">
              <div
                :for={%{group: group, option: option} <- @origins}
                id={"character-origin-#{group.id}"}
                class="flex gap-4"
              >
                <img
                  :if={option.image_path}
                  src={option.image_path}
                  alt=""
                  class="size-14 shrink-0 rounded object-cover"
                />
                <div class="min-w-0 flex-1">
                  <p class="notepad-text">
                    <span class="opacity-70">{group.name}:</span>
                    <strong id={"character-origin-option-#{option.id}"}>{option.name}</strong>
                    <span
                      :if={@full? and Origins.bonus_label(option.bonuses)}
                      id={"character-origin-bonuses-#{option.id}"}
                      class="ml-2 text-sm tabular-nums opacity-70"
                    >
                      ({Origins.bonus_label(option.bonuses)})
                    </span>
                  </p>

                  <.markdown
                    :if={option.description}
                    content={option.description}
                    class="notepad-text text-sm"
                  />
                </div>
              </div>
            </div>
          </div>

          <div :if={@guilds != []} id="character-guilds" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Guilds")}</p>

            <ul class="mt-2 flex flex-wrap gap-3">
              <li
                :for={membership <- @guilds}
                id={"character-guild-#{membership.guild_id}"}
              >
                <.link
                  navigate={~p"/g/#{@current_story}/guilds/#{membership.guild_id}"}
                  class="flex items-center gap-3 rounded-lg px-2 py-1 transition hover:bg-base-content/5"
                >
                  <.guild_emblem guild={membership.guild} class="size-10" />
                  <span class="notepad-text leading-tight">
                    <strong>{membership.guild.name}</strong>
                    <span :if={membership.rank} class="block text-sm opacity-70">
                      {membership.rank.name}
                    </span>
                  </span>
                </.link>
              </li>
            </ul>
          </div>

          <div :if={@quests != []} id="character-quests" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Quests")}</p>

            <ul class="notepad-text mt-1">
              <li :for={quest <- @quests} id={"character-quest-#{quest.id}"}>
                <.link
                  navigate={~p"/g/#{@current_story}/quests"}
                  class="transition hover:text-primary"
                >
                  {quest.title}
                </.link>

                <span class="text-sm opacity-70">
                  · {quest.game_date_label || Calendar.strftime(quest.held_on, "%d/%m/%Y")}
                </span>

                <span :if={quest.visibility == "masters"} class="text-sm opacity-70">
                  {dgettext("player", "· masters only")}
                </span>
              </li>
            </ul>
          </div>

          <.gallery_section
            :if={@diary? and (@gallery != [] or @gallery_manager?)}
            gallery={@gallery}
            manager?={@gallery_manager?}
            uploads={@uploads}
            form={@gallery_form}
            character={@character}
          />
          <div :if={@diary?} id="character-diary" class="mt-8">
            <p class="notepad-label flex items-center gap-2">
              {dgettext("player", "Diary")}
              <.link
                id="character-diary-link"
                navigate={~p"/g/#{@current_story}/characters/#{@character}/diary"}
                class="ml-auto normal-case tracking-normal text-sm underline decoration-dotted underline-offset-4 transition hover:text-[#0f1a13]"
              >
                {if @diary_writer?,
                  do: dgettext("player", "Open & write"),
                  else: dgettext("player", "Read the diary")} →
              </.link>
            </p>

            <p
              :if={@diary_entries == []}
              id="character-diary-empty"
              class="notepad-text text-sm opacity-60"
            >
              {dgettext("player", "No pages written yet.")}
            </p>

            <ul class="notepad-text">
              <li
                :for={entry <- @diary_entries}
                id={"character-diary-entry-#{entry.id}"}
                class="flex flex-wrap items-baseline gap-x-3"
              >
                <.link
                  navigate={
                    ~p"/g/#{@current_story}/characters/#{@character}/diary#diary-entry-#{entry.id}"
                  }
                  class="font-semibold transition hover:underline"
                >
                  {entry.title}
                </.link>

                <span class="text-sm opacity-70">
                  {entry.game_date_label || Calendar.strftime(entry.inserted_at, "%d/%m/%Y")}
                </span>

                <span
                  :if={entry.visibility != "public"}
                  class="text-xs uppercase tracking-wider opacity-60"
                >
                  · {Diary.visibility_label(entry.visibility)}
                </span>
              </li>
            </ul>
          </div>

          <div :if={@character.off_game_info} id="character-off-game" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Off-game info")}</p>
            <.markdown content={@character.off_game_info} class="notepad-text" />
          </div>

          <div :for={{kind, entries} <- @sheet} :if={entries != []} id={"sheet-#{kind}"} class="mt-8">
            <p class="notepad-label">{Sheet.kind_label(kind)}</p>

            <ul class="notepad-text">
              <li
                :for={{item, value} <- entries}
                class="flex items-center justify-between gap-4"
                title={item.description}
              >
                <span>{item.name}</span>
                <span class="flex items-center gap-3">
                  <.raise_button
                    :if={@can_spend?}
                    item={item}
                    cost={@costs[item.id]}
                    available={@xp.available}
                  />
                  <span
                    :if={@bonuses[item.slug]}
                    id={"trait-bonus-#{item.id}"}
                    class="text-xs tabular-nums opacity-60"
                    title={dgettext("player", "Base value and bonus (origins and equipment)")}
                  >
                    {value} {Origins.signed(@bonuses[item.slug])}
                  </span>

                  <span id={"trait-value-#{item.id}"} class="font-bold">
                    {value + (@bonuses[item.slug] || 0)}
                  </span>
                </span>
              </li>
            </ul>
          </div>

          <div
            :if={@items_on? and (@full? or @inventory != [])}
            id="character-inventory"
            class="mt-8"
          >
            <p class="notepad-label">
              {if @full?,
                do: dgettext("player", "Inventory & equipment"),
                else: dgettext("player", "Equipment")}
            </p>

            <p :if={@inventory == []} id="inventory-empty" class="notepad-text text-sm opacity-60">
              {dgettext("player", "Empty pockets.")}
            </p>

            <ul class="notepad-text">
              <li
                :for={stack <- @inventory}
                id={"inventory-item-#{stack.item.id}"}
                class="flex flex-wrap items-center gap-x-3 gap-y-1 py-1"
              >
                <img
                  :if={stack.item.image_path}
                  src={stack.item.image_path}
                  alt=""
                  class="size-8 shrink-0 rounded object-cover"
                />
                <span class="min-w-0 flex-1">
                  <span class="font-semibold">{stack.item.name}</span>
                  <span :if={@full? and stack.quantity > 1} class="tabular-nums opacity-70">
                    ×{stack.quantity}
                  </span>

                  <span
                    :if={stack.equipped}
                    id={"inventory-equipped-#{stack.item.id}"}
                    class="ml-1 text-xs font-bold uppercase tracking-wider opacity-70"
                  >
                    [{stack.item.slot}]
                  </span>

                  <span
                    :if={Origins.bonus_label(stack.item.modifiers)}
                    class="ml-1 text-xs tabular-nums opacity-60"
                  >
                    {Origins.bonus_label(stack.item.modifiers)}
                  </span>
                </span>

                <span :if={@full?} class="flex shrink-0 gap-1">
                  <button
                    :if={
                      (@item_player? or @item_master?) and Item.equippable?(stack.item) and
                        not stack.equipped
                    }
                    id={"equip-item-#{stack.item.id}"}
                    phx-click="equip_item"
                    phx-value-item={stack.item.id}
                    class="btn btn-xs console-action"
                  >
                    {dgettext("player", "Equip")}
                  </button>

                  <button
                    :if={(@item_player? or @item_master?) and stack.equipped}
                    id={"unequip-item-#{stack.item.id}"}
                    phx-click="unequip_item"
                    phx-value-item={stack.item.id}
                    class="btn btn-xs console-action"
                  >
                    {dgettext("player", "Unequip")}
                  </button>

                  <button
                    :if={@item_player? and Item.usable?(stack.item)}
                    id={"use-item-#{stack.item.id}"}
                    phx-click="use_item"
                    phx-value-item={stack.item.id}
                    class="btn btn-xs console-action"
                    title={
                      stack.item.tracker &&
                        "#{stack.item.tracker.name} #{Origins.signed(stack.item.effect_change)}"
                    }
                  >
                    {dgettext("player", "Use")}
                  </button>

                  <button
                    :if={@item_master?}
                    id={"remove-item-#{stack.item.id}"}
                    phx-click="remove_item"
                    phx-value-item={stack.item.id}
                    data-confirm={dgettext("player", "Remove one unit of this item?")}
                    class="btn btn-xs console-action"
                    title={dgettext("player", "Remove one")}
                  >
                    <.icon name="hero-minus-micro" class="size-3" />
                  </button>
                </span>
              </li>
            </ul>

            <.form
              :if={@item_player? and @inventory != [] and @give_recipients != []}
              for={@give_form}
              id="give-item-form"
              phx-submit="give_item"
              class="mt-2 flex flex-wrap items-end gap-2 text-sm"
            >
              <select
                name="give[item_id]"
                class="select select-xs"
                aria-label={dgettext("player", "Item")}
              >
                <option :for={stack <- @inventory} value={stack.item.id}>{stack.item.name}</option>
              </select>

              <input
                type="number"
                name="give[quantity]"
                value="1"
                min="1"
                aria-label={dgettext("player", "Quantity")}
                class="input input-xs w-16"
              />
              <select
                name="give[to]"
                class="select select-xs"
                aria-label={dgettext("player", "Give to")}
              >
                <option :for={c <- @give_recipients} value={c.id}>{c.name}</option>
              </select>
              <button class="btn btn-xs console-action">{dgettext("player", "Give")}</button>
            </.form>
          </div>

          <div :if={@trackers != []} id="trackers" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Trackers")}</p>

            <div
              :for={state <- @trackers}
              id={"tracker-#{state.tracker.id}"}
              class="notepad-text mt-2"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <span>{state.tracker.name}</span>
                <span id={"tracker-value-#{state.tracker.id}"} class="font-bold tabular-nums">
                  {state.value} / {state.max}
                </span>
              </div>
              <.tracker_boxes state={state} />
              <p :if={state.tracker.damage_types != []} class="text-xs opacity-70">
                <span :for={{type, amount} <- state.damage} class="mr-3">{type}: {amount}</span>
              </p>

              <p :if={state.error} class="text-xs text-error">{state.error}</p>

              <.form
                :if={@tracker_master?}
                for={%{}}
                id={"tracker-edit-#{state.tracker.id}"}
                phx-submit="set_tracker"
                class="mt-1 flex flex-wrap items-end gap-2 text-sm"
              >
                <input type="hidden" name="tracker_id" value={state.tracker.id} />
                <label :if={state.tracker.damage_types == []} class="flex items-center gap-2">
                  <span class="text-xs">{dgettext("player", "Value")}</span>
                  <input
                    type="number"
                    name="value"
                    value={state.value}
                    min="0"
                    max={state.max}
                    class="input input-xs w-20"
                  />
                </label>

                <label
                  :for={{type, amount} <- state.damage}
                  class="flex items-center gap-2"
                >
                  <span class="text-xs">{type}</span>
                  <input
                    type="number"
                    name={"damage[#{type}]"}
                    value={amount}
                    min="0"
                    max={state.max}
                    class="input input-xs w-20"
                  />
                </label>
                <button class="btn btn-xs console-action">{dgettext("player", "Set")}</button>
              </.form>
            </div>
          </div>

          <div :if={@full?} id="experience" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Experience")}</p>

            <p id="xp-totals" class="notepad-text flex flex-wrap gap-x-6">
              <span>{dgettext("player", "Earned")} <strong id="xp-earned">{@xp.earned}</strong></span>
              <span>{dgettext("player", "Spent")} <strong id="xp-spent">{@xp.spent}</strong></span>
              <span>{dgettext("player", "Available")}
              <strong id="xp-available">{@xp.available}</strong></span>
            </p>

            <p :if={@owner? and not @can_spend?} class="text-xs opacity-70">
              {dgettext("player", "XP can be spent once the character is approved and can play.")}
            </p>

            <ul id="xp-log" class="notepad-text mt-2 text-sm">
              <li :if={@xp_entries == []} class="opacity-60">
                {dgettext("player", "No XP recorded yet.")}
              </li>

              <li :for={entry <- @xp_entries} id={"xp-entry-#{entry.id}"} class="flex gap-3">
                <span class="w-12 shrink-0 text-right font-bold tabular-nums">
                  {xp_amount(entry)}
                </span>
                <span class="min-w-0 flex-1">{xp_description(entry)}</span>
                <time
                  class="shrink-0 text-xs opacity-60"
                  datetime={DateTime.to_iso8601(entry.inserted_at)}
                >
                  {Calendar.strftime(entry.inserted_at, "%d/%m/%Y")}
                </time>
              </li>
            </ul>
          </div>

          <div :if={@full? and @character.player_notes} id="character-player-notes" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Player notes (private)")}</p>

            <p class="notepad-text whitespace-pre-line">{@character.player_notes}</p>
          </div>

          <div :if={@reviewer? and @character.master_notes} id="character-master-notes" class="mt-8">
            <p class="notepad-label">{dgettext("player", "Master notes (hidden from the player)")}</p>

            <p class="notepad-text whitespace-pre-line">{@character.master_notes}</p>
          </div>

          <p class="notepad-stamp">
            {if @character.is_npc,
              do: dgettext("player", "Non-player character"),
              else:
                dgettext("player", "Filed by %{value}",
                  value: TannhauserGate.Accounts.User.handle(@character.user)
                )}
          </p>
        </div>
      </article>
    </Layouts.app>
    """
  end

  attr :gallery, :list, required: true
  attr :manager?, :boolean, required: true
  attr :uploads, :map, required: true
  attr :form, :any, required: true
  attr :character, :map, required: true

  defp gallery_section(assigns) do
    errors =
      upload_errors(assigns.uploads.gallery) ++
        Enum.flat_map(
          assigns.uploads.gallery.entries,
          &upload_errors(assigns.uploads.gallery, &1)
        )

    assigns =
      assigns
      |> assign(:errors, Enum.map(errors, &gallery_upload_error/1))
      |> assign(:full?, length(assigns.gallery) >= Diary.max_images())

    ~H"""
    <div id="character-gallery" class="mt-8">
      <p class="notepad-label">
        {dgettext("player", "Gallery")}
        <span :if={@manager?} class="ml-1 tabular-nums opacity-70">
          {length(@gallery)}/{Diary.max_images()}
        </span>
      </p>

      <p :if={@gallery == []} id="character-gallery-empty" class="notepad-text text-sm opacity-60">
        {dgettext("player", "No pictures yet.")}
      </p>

      <ul class="mt-3 grid grid-cols-2 gap-5 sm:grid-cols-3">
        <li
          :for={{image, index} <- Enum.with_index(@gallery)}
          id={"gallery-image-#{image.id}"}
          class={[
            "polaroid group relative transition duration-200 hover:z-10 hover:rotate-0 hover:scale-105",
            if(rem(index, 2) == 0, do: "rotate-2", else: "-rotate-2")
          ]}
        >
          <figure>
            <a href={image.path} target="_blank" rel="noopener" class="block">
              <img
                src={image.path}
                alt={image.caption || dgettext("player", "Picture of %{name}", name: @character.name)}
                class="aspect-square w-full object-cover"
                loading="lazy"
              />
            </a>

            <figcaption class="min-h-[1.2rem] truncate" title={image.caption}>
              {image.caption}
            </figcaption>
          </figure>

          <button
            :if={@manager?}
            type="button"
            id={"gallery-delete-#{image.id}"}
            phx-click="delete_image"
            phx-value-id={image.id}
            data-confirm={dgettext("player", "Remove this picture?")}
            class="absolute -right-2 -top-2 grid size-6 place-items-center rounded-full bg-error text-error-content opacity-0 shadow transition group-hover:opacity-100 focus:opacity-100"
            aria-label={dgettext("player", "Remove picture")}
          >
            <.icon name="hero-x-mark-micro" class="size-4" />
          </button>
        </li>
      </ul>

      <.form
        :if={@manager? and not @full?}
        for={@form}
        id="gallery-form"
        phx-change="validate_gallery"
        phx-submit="add_image"
        class="mt-4 flex flex-wrap items-end gap-2 text-sm"
      >
        <div phx-drop-target={@uploads.gallery.ref} class="flex items-center gap-2">
          <.live_img_preview
            :for={entry <- @uploads.gallery.entries}
            entry={entry}
            class="size-12 rounded object-cover ring-2 ring-[#1d6b40]"
          />
          <.live_file_input
            upload={@uploads.gallery}
            class="file-input file-input-xs w-56"
            aria-describedby="gallery-hint"
          />
        </div>

        <input
          type="text"
          name="gallery[caption]"
          value={@form[:caption].value}
          maxlength="140"
          placeholder={dgettext("player", "Caption")}
          aria-label={dgettext("player", "Caption")}
          class="input input-xs w-48"
        />
        <button
          class="btn btn-xs console-action"
          phx-disable-with={dgettext("player", "Uploading...")}
        >
          <.icon name="hero-photo-micro" class="size-3" /> {dgettext("player", "Add picture")}
        </button>

        <button
          :for={entry <- @uploads.gallery.entries}
          type="button"
          phx-click="cancel_gallery_upload"
          phx-value-ref={entry.ref}
          class="btn btn-ghost btn-xs"
        >
          {dgettext("player", "Cancel")}
        </button>

        <p id="gallery-hint" class="w-full text-xs opacity-60">
          {dgettext("player", "PNG, JPEG or WebP, max 5 MB.")}
        </p>

        <p :for={error <- @errors} class="gallery-error w-full text-xs text-error">{error}</p>
      </.form>
    </div>
    """
  end

  defp gallery_upload_error(:too_large),
    do: dgettext("player", "The image is too large (max 5 MB)")

  defp gallery_upload_error(:not_accepted),
    do: dgettext("player", "Only PNG, JPEG and WebP images are allowed")

  defp gallery_upload_error(:too_many_files), do: dgettext("player", "One picture at a time")

  defp gallery_upload_error(other),
    do: dgettext("player", "Upload error: %{value}", value: inspect(other))

  attr :item, :map, required: true
  attr :cost, :any, required: true
  attr :available, :integer, required: true

  defp raise_button(%{cost: {:ok, cost}} = assigns) do
    assigns = assign(assigns, :amount, cost)

    ~H"""
    <button
      type="button"
      id={"raise-#{@item.id}"}
      phx-click="raise"
      phx-value-item={@item.id}
      disabled={@amount > @available}
      data-confirm={
        dgettext("player", "Spend %{amount} XP to raise %{name}?", amount: @amount, name: @item.name)
      }
      class="btn btn-ghost btn-xs console-action"
      title={dgettext("player", "Raise for %{amount} XP", amount: @amount)}
    >
      +1 · {@amount} XP
    </button>
    """
  end

  defp raise_button(assigns), do: ~H""

  attr :state, :map, required: true

  # One box per point of the maximum (capped), filled by the current value
  # or by the damage of each type.
  defp tracker_boxes(assigns) do
    marks =
      if assigns.state.tracker.damage_types == [] do
        List.duplicate(:full, assigns.state.value)
      else
        assigns.state.tracker.damage_types
        |> Enum.with_index()
        |> Enum.reverse()
        |> Enum.flat_map(fn {type, index} ->
          List.duplicate({:damage, index}, Map.get(assigns.state.damage, type, 0))
        end)
      end

    empty = List.duplicate(:empty, max(assigns.state.max - length(marks), 0))
    assigns = assign(assigns, :marks, Enum.take(marks ++ empty, 30))

    ~H"""
    <div class="mt-1 flex flex-wrap gap-1" aria-hidden="true">
      <span
        :for={mark <- @marks}
        class={[
          "inline-block size-3 rounded-sm border border-current",
          mark_class(mark)
        ]}
      ></span>
    </div>
    """
  end

  defp mark_class(:full), do: "bg-current"
  defp mark_class(:empty), do: "opacity-40"
  defp mark_class({:damage, 0}), do: "bg-current opacity-50"
  defp mark_class({:damage, _}), do: "bg-current"

  defp xp_amount(%{kind: "spend", amount: amount}), do: "−#{amount}"
  defp xp_amount(%{amount: amount}) when amount > 0, do: "+#{amount}"
  defp xp_amount(%{amount: amount}), do: "−#{abs(amount)}"

  defp xp_description(%{kind: "spend"} = entry),
    do: "#{entry.item_name}: #{entry.from_value} → #{entry.to_value}"

  defp xp_description(entry) do
    by = if entry.author, do: " (#{entry.author.username})", else: ""
    "#{entry.reason}#{by}"
  end

  defp state_label(state),
    do:
      if(state.can_play,
        do: state.name,
        else: dgettext("player", "%{name} (cannot play)", name: state.name)
      )

  defp approval_class("approved"), do: "border-success/40 bg-success/10"
  defp approval_class("rejected"), do: "border-error/40 bg-error/10"
  defp approval_class("submitted"), do: "border-info/40 bg-info/10"
  defp approval_class(_), do: "border-warning/40 bg-warning/10"

  defp approval_icon("approved"), do: "hero-check-badge"
  defp approval_icon("rejected"), do: "hero-x-circle"
  defp approval_icon("submitted"), do: "hero-clock"
  defp approval_icon(_), do: "hero-pencil-square"

  defp approval_hint(%{approval_status: "approved"} = character, _owner?) do
    if Characters.can_play?(character),
      do: dgettext("player", "Approved: this character can play."),
      else: dgettext("player", "Approved, but the current state does not allow playing.")
  end

  defp approval_hint(%{approval_status: "submitted"}, _owner?),
    do:
      dgettext(
        "player",
        "Waiting for a master to review it. Until then it cannot speak in the chat rooms."
      )

  defp approval_hint(%{approval_status: "rejected"}, true),
    do: dgettext("player", "Rejected: edit it following the notes below and submit it again.")

  defp approval_hint(%{approval_status: "rejected"}, _owner?),
    do: dgettext("player", "Rejected: the player can edit it and submit it again.")

  defp approval_hint(_character, true),
    do:
      dgettext("player", "Draft: you can use every feature except playing. Submit it when ready.")

  defp approval_hint(_character, _owner?), do: dgettext("player", "Draft: not submitted yet.")
end
