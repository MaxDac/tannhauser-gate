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
       |> put_flash(:error, "That character does not exist in this GDR.")
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
    |> assign(:item_master?, master?)
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
       |> put_flash(:info, "Character deleted")
       |> push_navigate(to: ~p"/g/#{socket.assigns.current_story}/characters")}
    else
      {:noreply, put_flash(socket, :error, "You can't delete this character.")}
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
         |> put_flash(:info, "Picture added to the gallery")
         |> assign(:gallery_form, to_form(%{"caption" => ""}, as: :gallery))
         |> reload()}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, Diary.error_message(reason))}

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a picture first.")}
    end
  end

  def handle_event("delete_image", %{"id" => id}, socket) do
    %{character: character, current_user: user} = socket.assigns

    case Diary.delete_image(user, character, id) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Picture removed") |> reload()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Diary.error_message(reason))}
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

  def handle_event("raise", %{"item" => item_id}, socket) do
    %{character: character, current_user: user} = socket.assigns

    case Experience.spend(user, character, item_id) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{entry.item_name} raised to #{entry.to_value} (#{entry.amount} XP)"
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
        {:noreply, socket |> put_flash(:info, "#{entry.amount} XP recorded") |> reload()}

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
          {:noreply, socket |> put_flash(:info, "#{tracker.name} updated") |> reload()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Trackers.error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the GDR masters can change trackers.")}
    end
  end

  def handle_event("equip_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_player? or socket.assigns.item_master?, fn c, u ->
      with {:ok, %{item: item}} <- Items.equip(c, item_id, u), do: {:ok, "#{item.name} equipped"}
    end)
  end

  def handle_event("unequip_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_player? or socket.assigns.item_master?, fn c, u ->
      with {:ok, %{item: item}} <- Items.unequip(c, item_id, u),
           do: {:ok, "#{item.name} unequipped"}
    end)
  end

  def handle_event("use_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_player?, fn c, u ->
      with {:ok, %{item: item, state: state}} <- Items.use_item(c, item_id, u),
           do: {:ok, "#{item.name} used: #{state.tracker.name} #{state.value}/#{state.max}"}
    end)
  end

  def handle_event("remove_item", %{"item" => item_id}, socket) do
    item_action(socket, socket.assigns.item_master?, fn c, u ->
      with {:ok, %{item: item}} <- Items.remove(c, item_id, 1, u, "From the sheet"),
           do: {:ok, "1× #{item.name} removed"}
    end)
  end

  def handle_event("give_item", %{"give" => params}, socket) do
    item_action(socket, socket.assigns.item_player?, fn c, u ->
      with {:ok, %{item: item, quantity: qty, to: to}} <-
             Items.give(c, params["to"], params["item_id"], params["quantity"], u),
           do: {:ok, "Gave #{qty}× #{item.name} to #{to.name}"}
    end)
  end

  defp item_action(socket, allowed?, fun) do
    if allowed? do
      case fun.(socket.assigns.character, socket.assigns.current_user) do
        {:ok, message} -> {:noreply, socket |> put_flash(:info, message) |> reload()}
        {:error, reason} -> {:noreply, put_flash(socket, :error, Items.error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "You can't manage this character's items.")}
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
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
        <.link
          navigate={~p"/g/#{@current_story}/characters"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Back to characters
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
            <.icon name="hero-envelope" class="size-4" /> Send message
          </.button>

          <div :if={@can_edit?} class="contents">
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

        <div class="sm:col-span-2">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Award XP</h2>
          <.form
            for={@award_form}
            id="xp-award-form"
            phx-submit="award_xp"
            class="grid gap-x-3 sm:grid-cols-[8rem_1fr_auto] sm:items-end"
          >
            <.input
              field={@award_form[:amount]}
              type="number"
              label="Amount (negative to correct)"
              required
            />
            <.input field={@award_form[:reason]} type="text" label="Reason" required />
            <.button class="btn btn-sm console-action mb-2">Record</.button>
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

              <.markdown
                id="character-description"
                content={@character.description || "—"}
                class="notepad-text"
              />

              <p class="notepad-label mt-4">Job</p>

              <p id="character-job" class="notepad-text">
                {(@character.job && @character.job.name) || "—"}
              </p>
            </div>
          </div>

          <p class="notepad-label mt-8">Background</p>

          <.markdown
            id="character-background"
            content={@character.background || "—"}
            class="notepad-text"
          />

          <div :if={@origins != []} id="character-origins" class="mt-8">
            <p class="notepad-label">Origins</p>
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
            <p class="notepad-label">Guilds</p>
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
            <p class="notepad-label">Quests</p>
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
                  · masters only
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
              Diary
              <.link
                id="character-diary-link"
                navigate={~p"/g/#{@current_story}/characters/#{@character}/diary"}
                class="ml-auto normal-case tracking-normal text-sm underline decoration-dotted underline-offset-4 transition hover:text-[#0f1a13]"
              >
                {if @diary_writer?, do: "Open & write", else: "Read the diary"} →
              </.link>
            </p>
            <p
              :if={@diary_entries == []}
              id="character-diary-empty"
              class="notepad-text text-sm opacity-60"
            >
              No pages written yet.
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
            <p class="notepad-label">Off-game info</p>
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
                    title="Base value and bonus (origins and equipment)"
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
            <p class="notepad-label">{if @full?, do: "Inventory & equipment", else: "Equipment"}</p>
            <p :if={@inventory == []} id="inventory-empty" class="notepad-text text-sm opacity-60">
              Empty pockets.
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
                    Equip
                  </button>
                  <button
                    :if={(@item_player? or @item_master?) and stack.equipped}
                    id={"unequip-item-#{stack.item.id}"}
                    phx-click="unequip_item"
                    phx-value-item={stack.item.id}
                    class="btn btn-xs console-action"
                  >
                    Unequip
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
                    Use
                  </button>
                  <button
                    :if={@item_master?}
                    id={"remove-item-#{stack.item.id}"}
                    phx-click="remove_item"
                    phx-value-item={stack.item.id}
                    data-confirm="Remove one unit of this item?"
                    class="btn btn-xs console-action"
                    title="Remove one"
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
              <select name="give[item_id]" class="select select-xs" aria-label="Item">
                <option :for={stack <- @inventory} value={stack.item.id}>{stack.item.name}</option>
              </select>
              <input
                type="number"
                name="give[quantity]"
                value="1"
                min="1"
                aria-label="Quantity"
                class="input input-xs w-16"
              />
              <select name="give[to]" class="select select-xs" aria-label="Give to">
                <option :for={c <- @give_recipients} value={c.id}>{c.name}</option>
              </select>
              <button class="btn btn-xs console-action">Give</button>
            </.form>
          </div>

          <div :if={@trackers != []} id="trackers" class="mt-8">
            <p class="notepad-label">Trackers</p>

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
                  <span class="text-xs">Value</span>
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
                <button class="btn btn-xs console-action">Set</button>
              </.form>
            </div>
          </div>

          <div :if={@full?} id="experience" class="mt-8">
            <p class="notepad-label">Experience</p>
            <p id="xp-totals" class="notepad-text flex flex-wrap gap-x-6">
              <span>Earned <strong id="xp-earned">{@xp.earned}</strong></span>
              <span>Spent <strong id="xp-spent">{@xp.spent}</strong></span>
              <span>Available <strong id="xp-available">{@xp.available}</strong></span>
            </p>
            <p :if={@owner? and not @can_spend?} class="text-xs opacity-70">
              XP can be spent once the character is approved and can play.
            </p>

            <ul id="xp-log" class="notepad-text mt-2 text-sm">
              <li :if={@xp_entries == []} class="opacity-60">No XP recorded yet.</li>
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
        Gallery
        <span :if={@manager?} class="ml-1 tabular-nums opacity-70">
          {length(@gallery)}/{Diary.max_images()}
        </span>
      </p>
      <p :if={@gallery == []} id="character-gallery-empty" class="notepad-text text-sm opacity-60">
        No pictures yet.
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
                alt={image.caption || "Picture of #{@character.name}"}
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
            data-confirm="Remove this picture?"
            class="absolute -right-2 -top-2 grid size-6 place-items-center rounded-full bg-error text-error-content opacity-0 shadow transition group-hover:opacity-100 focus:opacity-100"
            aria-label="Remove picture"
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
          placeholder="Caption"
          aria-label="Caption"
          class="input input-xs w-48"
        />
        <button class="btn btn-xs console-action" phx-disable-with="Uploading...">
          <.icon name="hero-photo-micro" class="size-3" /> Add picture
        </button>
        <button
          :for={entry <- @uploads.gallery.entries}
          type="button"
          phx-click="cancel_gallery_upload"
          phx-value-ref={entry.ref}
          class="btn btn-ghost btn-xs"
        >
          Cancel
        </button>
        <p id="gallery-hint" class="w-full text-xs opacity-60">PNG, JPEG or WebP, max 5 MB.</p>
        <p :for={error <- @errors} class="gallery-error w-full text-xs text-error">{error}</p>
      </.form>
    </div>
    """
  end

  defp gallery_upload_error(:too_large), do: "The image is too large (max 5 MB)"
  defp gallery_upload_error(:not_accepted), do: "Only PNG, JPEG and WebP images are allowed"
  defp gallery_upload_error(:too_many_files), do: "One picture at a time"
  defp gallery_upload_error(other), do: "Upload error: #{inspect(other)}"

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
      data-confirm={"Spend #{@amount} XP to raise #{@item.name}?"}
      class="btn btn-ghost btn-xs console-action"
      title={"Raise for #{@amount} XP"}
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
    do: if(state.can_play, do: state.name, else: "#{state.name} (cannot play)")

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
      do: "Approved: this character can play.",
      else: "Approved, but the current state does not allow playing."
  end

  defp approval_hint(%{approval_status: "submitted"}, _owner?),
    do: "Waiting for a master to review it. Until then it cannot speak in the chat rooms."

  defp approval_hint(%{approval_status: "rejected"}, true),
    do: "Rejected: edit it following the notes below and submit it again."

  defp approval_hint(%{approval_status: "rejected"}, _owner?),
    do: "Rejected: the player can edit it and submit it again."

  defp approval_hint(_character, true),
    do: "Draft: you can use every feature except playing. Submit it when ready."

  defp approval_hint(_character, _owner?), do: "Draft: not submitted yet."
end
