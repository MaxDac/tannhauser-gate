defmodule TannhauserGateWeb.MasterLive.Quests do
  @moduledoc """
  Masters record the quests they ran (quests module): title, Markdown
  summary, date, room, visibility and an optional chat-log range, plus the
  participants with their rewards (XP, money, an item with the items
  module). "Record and award" hands out every reward at once, all or
  nothing, and only once.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Calendars, Items, Quests, Stories}
  alias TannhauserGate.Quests.{Participant, Quest}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :quests}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "Quests")
     |> assign(:locations, Stories.list_locations(story))
     |> assign(:items, if(Items.enabled?(story), do: Items.list_items(story), else: []))
     |> reload()
     |> edit_quest(new_quest(socket))}
  end

  defp story(socket), do: socket.assigns.current_story

  defp new_quest(socket) do
    %Quest{
      participants: [],
      held_on: Date.utc_today(),
      game_date_label: Calendars.current_label(story(socket)),
      visibility: "public"
    }
  end

  defp reload(socket) do
    assign(socket, :quests, Quests.list_quests(story(socket), socket.assigns.current_user))
  end

  defp edit_quest(socket, quest) do
    socket
    |> assign(:quest, quest)
    |> assign(:form, to_form(Quests.change_quest(quest)))
    |> assign(
      :candidates,
      if(quest.id, do: Quests.participant_candidates(story(socket), quest), else: [])
    )
    |> edit_participant(%Participant{})
  end

  defp edit_participant(socket, participant) do
    socket
    |> assign(:participant, participant)
    |> assign(:participant_form, to_form(Quests.change_participant(participant)))
  end

  defp refresh_quest(socket) do
    socket = reload(socket)

    case Quests.get_quest(story(socket), socket.assigns.quest.id) do
      nil -> edit_quest(socket, new_quest(socket))
      quest -> edit_quest(socket, quest)
    end
  end

  @impl true
  def handle_event("validate", %{"quest" => params}, socket) do
    changeset = socket.assigns.quest |> Quests.change_quest(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"quest" => params}, socket) do
    %{current_user: user, quest: quest} = socket.assigns

    result =
      case quest do
        %Quest{id: nil} -> Quests.create_quest(user, story(socket), params)
        quest -> Quests.update_quest(user, story(socket), quest, params)
      end

    case result do
      {:ok, quest} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quest saved.")
         |> reload()
         |> edit_quest(quest)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Quests.error_message(reason))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Quests.get_quest(story(socket), id) do
      nil -> {:noreply, put_flash(socket, :error, Quests.error_message(:quest_not_found))}
      quest -> {:noreply, edit_quest(socket, quest)}
    end
  end

  def handle_event("new", _, socket), do: {:noreply, edit_quest(socket, new_quest(socket))}

  def handle_event("delete", %{"id" => id}, socket) do
    with %Quest{} = quest <- Quests.get_quest(story(socket), id),
         {:ok, _} <- Quests.delete_quest(socket.assigns.current_user, story(socket), quest) do
      socket = socket |> put_flash(:info, "Quest deleted.") |> reload()

      {:noreply,
       if(socket.assigns.quest.id == quest.id,
         do: edit_quest(socket, new_quest(socket)),
         else: socket
       )}
    else
      nil -> {:noreply, put_flash(socket, :error, Quests.error_message(:quest_not_found))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Quests.error_message(reason))}
    end
  end

  ## Participants

  def handle_event("save_participant", %{"participant" => params}, socket) do
    %{current_user: user, quest: quest, participant: participant} = socket.assigns

    result =
      case participant do
        %Participant{id: nil} -> Quests.add_participant(user, story(socket), quest, params)
        p -> Quests.update_participant(user, story(socket), quest, p.id, params)
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Participant saved.") |> refresh_quest()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :participant_form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Quests.error_message(reason))}
    end
  end

  def handle_event("edit_participant", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.quest.participants, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      participant -> {:noreply, edit_participant(socket, participant)}
    end
  end

  def handle_event("cancel_participant", _, socket),
    do: {:noreply, edit_participant(socket, %Participant{})}

  def handle_event("remove_participant", %{"id" => id}, socket) do
    %{current_user: user, quest: quest} = socket.assigns

    case Quests.remove_participant(user, story(socket), quest, id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Participant removed.") |> refresh_quest()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Quests.error_message(reason))}
    end
  end

  def handle_event("apply_rewards", _, socket) do
    %{current_user: user, quest: quest} = socket.assigns

    case Quests.apply_rewards(user, story(socket), quest) do
      {:ok, quest} ->
        {:noreply,
         socket
         |> put_flash(:info, "Quest recorded: the rewards were handed out.")
         |> reload()
         |> edit_quest(quest)}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Quests.error_message(reason)) |> refresh_quest()}
    end
  end

  defp reward_summary(participant, currency) do
    [
      participant.xp > 0 && "#{participant.xp} XP",
      participant.money > 0 && "#{participant.money} #{currency}",
      participant.item && "#{participant.item.name} × #{participant.item_quantity}"
    ]
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> "no rewards"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp datetime_value(form, field) do
    case form[field].value do
      %DateTime{} = dt ->
        dt
        |> DateTime.truncate(:second)
        |> DateTime.to_naive()
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      other ->
        other
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
      online={@online}
      last_location={@last_location}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <div class="mb-4 flex flex-wrap gap-4">
        <.link
          navigate={~p"/g/#{@current_story}/master"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master tools
        </.link>
        <.link
          navigate={~p"/g/#{@current_story}/quests"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          Public registry <.icon name="hero-arrow-right-solid" class="size-3" />
        </.link>
      </div>

      <.header>
        Quests
        <:subtitle>
          Record the quests you ran, who took part and what they earned. "Record and award"
          hands out every reward at once, and only once.
        </:subtitle>
        <:actions>
          <.button :if={@quest.id} id="new-quest" phx-click="new" class="btn btn-sm btn-secondary">
            <.icon name="hero-plus" class="size-4" /> New quest
          </.button>
        </:actions>
      </.header>

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_30rem]">
        <section id="master-quest-list">
          <p :if={@quests == []} id="quests-empty" class="text-sm text-base-content/60">
            No quests recorded yet.
          </p>
          <ul class="space-y-2">
            <li
              :for={quest <- @quests}
              id={"master-quest-#{quest.id}"}
              class={[
                "rounded-xl border bg-base-200/60 p-4 transition hover:-translate-y-0.5 hover:border-primary/40",
                if(@quest.id == quest.id, do: "border-primary/60", else: "border-secondary/20")
              ]}
            >
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <p class="truncate font-semibold text-primary">{quest.title}</p>
                  <p class="text-xs text-base-content/60">
                    {quest.game_date_label || Calendar.strftime(quest.held_on, "%d/%m/%Y")}
                    <span :if={quest.location}>· {quest.location.name}</span>
                    · {(quest.master && quest.master.username) || "—"} · {length(quest.participants)} participants
                  </p>
                  <div class="mt-1 flex flex-wrap gap-1">
                    <span class={[
                      "badge badge-soft badge-xs",
                      if(quest.visibility == "public", do: "badge-info", else: "badge-warning")
                    ]}>
                      {Quests.visibility_label(quest.visibility)}
                    </span>
                    <span
                      :if={Quest.rewarded?(quest)}
                      class="badge badge-soft badge-xs badge-success"
                    >
                      rewards handed out
                    </span>
                  </div>
                </div>
                <span class="flex shrink-0 gap-1">
                  <button
                    id={"edit-quest-#{quest.id}"}
                    phx-click="edit"
                    phx-value-id={quest.id}
                    class="rounded p-0.5 text-base-content/60 transition-colors hover:text-secondary"
                    title="Edit"
                  >
                    <.icon name="hero-pencil" class="size-4" />
                  </button>
                  <button
                    id={"delete-quest-#{quest.id}"}
                    phx-click="delete"
                    phx-value-id={quest.id}
                    data-confirm="Delete this quest? Rewards already handed out are kept."
                    class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                    title="Delete"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </span>
              </div>
            </li>
          </ul>
        </section>

        <div class="space-y-6">
          <section class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @quest.id, do: "Edit quest", else: "New quest"}
            </h2>
            <.form for={@form} id="quest-form" phx-change="validate" phx-submit="save" class="mt-4">
              <.input field={@form[:title]} type="text" label="Title" required />
              <.input field={@form[:summary]} type="textarea" label="Summary (Markdown)" rows="5" />
              <div class="grid gap-3 sm:grid-cols-2">
                <.input field={@form[:held_on]} type="date" label="Held on" required />
                <.input
                  field={@form[:visibility]}
                  type="select"
                  label="Visibility"
                  options={Enum.map(Quest.visibilities(), &{Quests.visibility_label(&1), &1})}
                />
              </div>
              <.input
                :if={Calendars.enabled?(@current_story)}
                field={@form[:game_date_label]}
                type="text"
                label="In-game date"
              />
              <.input
                field={@form[:location_id]}
                type="select"
                label="Room (optional)"
                prompt="—"
                options={Enum.map(@locations, &{&1.name, &1.id})}
              />
              <div class="grid gap-3 sm:grid-cols-2">
                <.input
                  field={@form[:log_from]}
                  value={datetime_value(@form, :log_from)}
                  type="datetime-local"
                  label="Chat log from (UTC)"
                />
                <.input
                  field={@form[:log_to]}
                  value={datetime_value(@form, :log_to)}
                  type="datetime-local"
                  label="Chat log to (UTC)"
                />
              </div>
              <div class="mt-2 flex gap-2">
                <.button id="save-quest" phx-disable-with="Saving...">
                  {if @quest.id, do: "Update quest", else: "Record quest"}
                </.button>
              </div>
            </.form>
          </section>

          <section
            :if={@quest.id}
            id="quest-participants"
            class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              Participants
            </h2>
            <p :if={Quest.rewarded?(@quest)} id="quest-rewarded" class="mt-1 text-xs text-success">
              <.icon name="hero-check-badge-micro" class="size-3" />
              Rewards handed out on {Calendar.strftime(@quest.rewards_applied_at, "%d/%m/%Y %H:%M")}
              <span :if={@quest.rewards_applied_by}>by {@quest.rewards_applied_by.username}</span>.
            </p>
            <ul class="mt-3 divide-y divide-secondary/10 text-sm">
              <li :if={@quest.participants == []} class="py-2 text-base-content/60">
                No participants yet.
              </li>
              <li
                :for={p <- @quest.participants}
                id={"participant-#{p.id}"}
                class="flex items-center justify-between gap-2 py-1.5"
              >
                <span class="min-w-0">
                  <span class="font-semibold">{p.character.name}</span>
                  <span class="block text-xs text-base-content/60">
                    {reward_summary(p, @current_story.currency_name)}
                    <span :if={p.note}>· {p.note}</span>
                  </span>
                </span>
                <span :if={!Quest.rewarded?(@quest)} class="flex gap-1">
                  <button
                    id={"edit-participant-#{p.id}"}
                    phx-click="edit_participant"
                    phx-value-id={p.id}
                    class="rounded p-0.5 text-base-content/60 transition-colors hover:text-secondary"
                    title="Edit"
                  >
                    <.icon name="hero-pencil" class="size-4" />
                  </button>
                  <button
                    id={"remove-participant-#{p.id}"}
                    phx-click="remove_participant"
                    phx-value-id={p.id}
                    class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                    title="Remove"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </span>
              </li>
            </ul>

            <.form
              :if={!Quest.rewarded?(@quest)}
              for={@participant_form}
              id="participant-form"
              phx-submit="save_participant"
              class="mt-4"
            >
              <.input
                :if={is_nil(@participant.id)}
                field={@participant_form[:character_id]}
                type="select"
                label="Character"
                options={Enum.map(@candidates, &{&1.name, &1.id})}
              />
              <p :if={@participant.id} class="mb-2 text-sm font-semibold">
                Rewards of {@participant.character.name}
              </p>
              <div class="grid grid-cols-2 gap-3">
                <.input field={@participant_form[:xp]} type="number" label="XP" min="0" />
                <.input
                  field={@participant_form[:money]}
                  type="number"
                  label={"Money (#{@current_story.currency_name})"}
                  min="0"
                />
              </div>
              <div :if={@items != []} class="grid grid-cols-[1fr_6rem] gap-3">
                <.input
                  field={@participant_form[:item_id]}
                  type="select"
                  label="Item"
                  prompt="—"
                  options={Enum.map(@items, &{&1.name, &1.id})}
                />
                <.input
                  field={@participant_form[:item_quantity]}
                  type="number"
                  label="Qty"
                  min="0"
                />
              </div>
              <.input field={@participant_form[:note]} type="text" label="Note" />
              <div class="flex gap-2">
                <.button
                  id="save-participant"
                  phx-disable-with="Saving..."
                  disabled={is_nil(@participant.id) && @candidates == []}
                >
                  {if @participant.id, do: "Update rewards", else: "Add participant"}
                </.button>
                <.button
                  :if={@participant.id}
                  type="button"
                  id="cancel-participant"
                  phx-click="cancel_participant"
                >
                  Cancel
                </.button>
              </div>
            </.form>

            <button
              :if={!Quest.rewarded?(@quest) && @quest.participants != []}
              id="apply-quest-rewards"
              phx-click="apply_rewards"
              data-confirm="Hand out every reward now? This can only be done once."
              class="btn btn-primary mt-5 w-full"
            >
              <.icon name="hero-gift" class="size-4" /> Record and award
            </button>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
