defmodule TannhauserGateWeb.MasterLive.Characters do
  @moduledoc """
  Master character dashboard: the approval queue and every character of the
  GDR (players and NPCs), filterable by approval status, state and NPC flag.
  Masters approve or reject characters, set their state, award XP (with the
  GDR XP log) and open their sheet to edit values, notes and trackers.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Experience}
  alias TannhauserGate.Characters.Character

  @filter_keys ~w(approval_status state_id npc)

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "Character dashboard")
     |> assign(:states, Characters.list_states(story))
     |> assign(:filters, Map.new(@filter_keys, &{&1, ""}))
     |> assign(
       :award_form,
       to_form(%{"character_id" => "", "amount" => "", "reason" => ""}, as: :award)
     )
     |> load_queue()
     |> load_xp()
     |> load_characters()}
  end

  defp load_xp(socket) do
    story = socket.assigns.current_story

    socket
    |> assign(:xp_totals, Experience.totals_by_character(story.id))
    |> assign(:xp_log, Experience.list_story_entries(story.id))
    |> assign(:award_options, award_options(story.id))
  end

  defp award_options(story_id) do
    story_id
    |> Characters.list_story_characters(%{})
    |> Enum.map(&{if(&1.is_npc, do: "#{&1.name} (NPC)", else: &1.name), &1.id})
  end

  defp load_queue(socket) do
    queue = Characters.list_approval_queue(socket.assigns.current_story.id)

    socket
    |> assign(:queue_count, length(queue))
    |> stream(:queue, queue, reset: true)
  end

  defp load_characters(socket) do
    %{current_story: story, filters: filters} = socket.assigns
    characters = Characters.list_story_characters(story.id, filters)

    socket
    |> assign(:filter_form, to_form(filters, as: :filters))
    |> assign(:characters_count, length(characters))
    |> stream(:characters, characters, reset: true)
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = Map.new(@filter_keys, &{&1, Map.get(params, &1, "")})
    {:noreply, socket |> assign(:filters, filters) |> load_characters()}
  end

  def handle_event("review", %{"character_id" => id, "decision" => decision} = params, socket) do
    notes = get_in(params, ["review", "notes"])

    with {:ok, character} <- fetch_character(socket, id),
         {:ok, updated} <- decide(decision, character, socket.assigns.current_user, notes) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "#{updated.name}: #{Characters.approval_label(updated.approval_status)}"
       )
       |> load_queue()
       |> load_characters()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Characters.approval_error_message(reason))}
    end
  end

  def handle_event(
        "set_state",
        %{"character_id" => id, "character_state" => %{"state_id" => state_id}},
        socket
      ) do
    with {:ok, character} <- fetch_character(socket, id),
         {:ok, _} <- Characters.set_state(character, state_id) do
      {:noreply, socket |> put_flash(:info, "State updated") |> load_characters()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Characters.approval_error_message(reason))}
    end
  end

  def handle_event("award_xp", %{"award" => params}, socket) do
    with {:ok, character} <- fetch_character(socket, params["character_id"]),
         {:ok, entry} <-
           Experience.award(
             socket.assigns.current_user,
             character,
             params["amount"],
             params["reason"]
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "#{character.name}: #{entry.amount} XP recorded")
       |> assign(
         :award_form,
         to_form(%{"character_id" => "", "amount" => "", "reason" => ""}, as: :award)
       )
       |> load_xp()
       |> load_characters()}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Experience.error_message(reason))
         |> assign(:award_form, to_form(params, as: :award))}
    end
  end

  defp decide("approve", character, user, notes),
    do: Characters.approve_character(character, user, notes)

  defp decide("reject", character, user, notes),
    do: Characters.reject_character(character, user, notes)

  defp decide(_, _, _, _), do: {:error, :invalid_status}

  defp fetch_character(socket, id) do
    with {int_id, ""} <- Integer.parse(to_string(id)),
         %{} = character <- Characters.get_character(int_id),
         true <- character.story_id == socket.assigns.current_story.id do
      {:ok, character}
    else
      _ -> {:error, :unauthorized}
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
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/master"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master tools
        </.link>
      </div>

      <.header>
        Character dashboard
        <:subtitle>Review, approve and run every character of {@current_story.name}.</:subtitle>
        <:actions>
          <.button id="new-npc" navigate={~p"/g/#{@current_story}/master/npcs/new"}>
            <.icon name="hero-user-plus" class="size-4" /> New NPC
          </.button>
        </:actions>
      </.header>

      <section id="approval-queue-section" class="mt-8">
        <h2 class="flex items-center gap-2 text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          Approval queue
          <span id="approval-queue-count" class="badge badge-sm badge-info badge-soft">
            {@queue_count}
          </span>
        </h2>

        <ul id="approval-queue" phx-update="stream" class="mt-3 grid gap-4 lg:grid-cols-2">
          <li id="approval-queue-empty" class="hidden text-sm text-base-content/60 only:block">
            No characters waiting for approval.
          </li>
          <li
            :for={{dom_id, character} <- @streams.queue}
            id={dom_id}
            class="rounded-xl border border-info/30 bg-base-200/80 p-4 transition hover:border-info/60"
          >
            <div class="flex items-center gap-3">
              <.avatar character={character} class="h-12 w-12 text-xl" />
              <div class="min-w-0">
                <.link
                  navigate={~p"/g/#{@current_story}/characters/#{character}"}
                  class="font-bold text-primary hover:underline"
                >
                  {character.name}
                </.link>
                <p class="text-xs text-base-content/60">by {character.user.username}</p>
              </div>
            </div>

            <form id={"review-form-#{character.id}"} phx-submit="review" class="mt-3 space-y-2">
              <input type="hidden" name="character_id" value={character.id} />
              <textarea
                name="review[notes]"
                rows="2"
                placeholder="Notes for the player (required to reject)"
                aria-label={"Review notes for #{character.name}"}
                class="textarea console-field w-full text-sm"
              ></textarea>
              <div class="flex gap-2">
                <button
                  id={"approve-#{character.id}"}
                  name="decision"
                  value="approve"
                  class="btn btn-success btn-sm console-action"
                >
                  Approve
                </button>
                <button
                  id={"reject-#{character.id}"}
                  name="decision"
                  value="reject"
                  class="btn btn-error btn-outline btn-sm console-action"
                >
                  Reject
                </button>
              </div>
            </form>
          </li>
        </ul>
      </section>

      <section id="all-characters" class="mt-10">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          All characters <span class="text-base-content/50">({@characters_count})</span>
        </h2>

        <.form
          for={@filter_form}
          id="character-filters"
          phx-change="filter"
          class="mt-3 grid gap-x-4 sm:grid-cols-3"
        >
          <.input
            field={@filter_form[:approval_status]}
            type="select"
            label="Approval"
            prompt="Any"
            options={Enum.map(Character.approval_statuses(), &{Characters.approval_label(&1), &1})}
          />
          <.input
            field={@filter_form[:state_id]}
            type="select"
            label="State"
            prompt="Any"
            options={[{"No state", "none"} | Enum.map(@states, &{&1.name, &1.id})]}
          />
          <.input
            field={@filter_form[:npc]}
            type="select"
            label="Kind"
            prompt="Any"
            options={[{"Players", "false"}, {"NPCs", "true"}]}
          />
        </.form>

        <div class="overflow-x-auto rounded-xl border border-secondary/20 bg-base-200/80">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Character</th>
                <th>Player</th>
                <th>Approval</th>
                <th>State</th>
                <th>XP</th>
                <th><span class="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody id="master-characters" phx-update="stream">
              <tr id="master-characters-empty" class="hidden only:table-row">
                <td colspan="6" class="text-center text-base-content/60">No matching characters.</td>
              </tr>
              <tr
                :for={{dom_id, character} <- @streams.characters}
                id={dom_id}
                class="transition hover:bg-base-300/40"
              >
                <td>
                  <.link
                    navigate={~p"/g/#{@current_story}/characters/#{character}"}
                    class="font-semibold text-primary hover:underline"
                  >
                    {character.name}
                  </.link>
                  <span :if={character.is_npc} class="badge badge-xs badge-secondary ml-1">NPC</span>
                </td>
                <td class="text-base-content/70">
                  {if character.is_npc, do: "—", else: character.user.username}
                </td>
                <td>
                  <span class={["badge badge-sm badge-soft", status_badge(character.approval_status)]}>
                    {Characters.approval_label(character.approval_status)}
                  </span>
                </td>
                <td>
                  <form
                    id={"state-form-#{character.id}"}
                    phx-change="set_state"
                  >
                    <input type="hidden" name="character_id" value={character.id} />
                    <select
                      name="character_state[state_id]"
                      aria-label={"State of #{character.name}"}
                      class="select select-xs console-field"
                    >
                      <option value="" selected={is_nil(character.state_id)}>No state</option>
                      <option
                        :for={state <- @states}
                        value={state.id}
                        selected={state.id == character.state_id}
                      >
                        {state.name}{if state.can_play, do: "", else: " (cannot play)"}
                      </option>
                    </select>
                  </form>
                </td>
                <td id={"xp-#{character.id}"} class="tabular-nums" title="Available / earned">
                  {xp_cell(@xp_totals, character.id)}
                </td>
                <td class="text-right">
                  <.link
                    id={"edit-#{character.id}"}
                    navigate={~p"/g/#{@current_story}/characters/#{character}/edit"}
                    class="text-sm font-semibold text-secondary hover:text-primary"
                  >
                    Edit sheet
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section id="experience-section" class="mt-10 grid gap-6 lg:grid-cols-2">
        <div>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Award XP</h2>
          <.form for={@award_form} id="xp-award-form" phx-submit="award_xp" class="mt-3">
            <.input
              field={@award_form[:character_id]}
              type="select"
              label="Character"
              prompt="Choose a character"
              options={@award_options}
              required
            />
            <.input
              field={@award_form[:amount]}
              type="number"
              label="Amount (negative to correct)"
              required
            />
            <.input field={@award_form[:reason]} type="text" label="Reason" required />
            <.button variant="primary" id="award-xp">Record XP</.button>
          </.form>
        </div>

        <div>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">XP log</h2>
          <ul id="story-xp-log" class="mt-3 space-y-1 text-sm">
            <li :if={@xp_log == []} class="text-base-content/60">No XP recorded yet.</li>
            <li :for={entry <- @xp_log} id={"story-xp-#{entry.id}"} class="flex gap-3">
              <span class="w-12 shrink-0 text-right font-bold tabular-nums">{xp_amount(entry)}</span>
              <span class="min-w-0 flex-1">
                <span class="font-semibold">{entry.character.name}</span> · {xp_description(entry)}
              </span>
              <time
                class="shrink-0 text-xs text-base-content/60"
                datetime={DateTime.to_iso8601(entry.inserted_at)}
              >
                {Calendar.strftime(entry.inserted_at, "%d/%m %H:%M")}
              </time>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp xp_cell(totals, id) do
    case Map.get(totals, id) do
      nil -> "0 / 0"
      %{available: available, earned: earned} -> "#{available} / #{earned}"
    end
  end

  defp xp_amount(%{kind: "spend", amount: amount}), do: "−#{amount}"
  defp xp_amount(%{amount: amount}) when amount > 0, do: "+#{amount}"
  defp xp_amount(%{amount: amount}), do: "−#{abs(amount)}"

  defp xp_description(%{kind: "spend"} = entry),
    do: "spent on #{entry.item_name}: #{entry.from_value} → #{entry.to_value}"

  defp xp_description(entry) do
    by = if entry.author, do: " (#{entry.author.username})", else: ""
    "#{entry.reason}#{by}"
  end

  defp status_badge("approved"), do: "badge-success"
  defp status_badge("rejected"), do: "badge-error"
  defp status_badge("submitted"), do: "badge-info"
  defp status_badge(_), do: "badge-warning"
end
