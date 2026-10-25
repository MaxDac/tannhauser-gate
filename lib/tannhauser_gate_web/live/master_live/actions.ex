defmodule TannhauserGateWeb.MasterLive.Actions do
  @moduledoc """
  Masters manage the periodic actions: per-character difficulty (for the
  actions whose difficulty is set per character), cooldown resets and the
  log of performed actions.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, PeriodicActions}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "Periodic actions")
     |> assign(:actions, PeriodicActions.list_actions(story))
     |> assign(
       :characters,
       Characters.list_story_characters(story.id, %{"approval_status" => "approved"})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    action =
      case params["action_id"] do
        nil -> List.first(socket.assigns.actions)
        id -> PeriodicActions.get_action!(socket.assigns.current_story, id)
      end

    {:noreply, socket |> assign(:action, action) |> load_action()}
  end

  defp load_action(%{assigns: %{action: nil}} = socket),
    do: assign(socket, difficulties: %{}, cooldowns: %{}, logs: [])

  defp load_action(socket) do
    action = socket.assigns.action
    now = DateTime.utc_now()

    socket
    |> assign(:difficulties, PeriodicActions.character_difficulties(action))
    |> assign(
      :cooldowns,
      Map.new(
        socket.assigns.characters,
        &{&1.id, PeriodicActions.cooldown_remaining(action, &1, now)}
      )
    )
    |> assign(:logs, PeriodicActions.list_logs(socket.assigns.current_story))
  end

  @impl true
  def handle_event("select_action", %{"action_id" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/g/#{socket.assigns.current_story}/master/actions?action_id=#{id}"
     )}
  end

  def handle_event("set_difficulty", %{"character_id" => id, "difficulty" => value}, socket) do
    character = find_character(socket, id)

    case PeriodicActions.set_difficulty(socket.assigns.action, character, value) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Difficulty of #{character.name} saved.") |> load_action()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "The difficulty must be between 0 and 100.")}
    end
  end

  def handle_event("reset_cooldown", %{"character-id" => id}, socket) do
    character = find_character(socket, id)
    {:ok, _} = PeriodicActions.reset_cooldown(socket.assigns.action, character)

    {:noreply,
     socket |> put_flash(:info, "Cooldown of #{character.name} reset.") |> load_action()}
  end

  defp find_character(socket, id) do
    id = if is_binary(id), do: String.to_integer(id), else: id

    Enum.find(socket.assigns.characters, &(&1.id == id)) ||
      raise Ecto.NoResultsError, queryable: Characters
  end

  defp format_cooldown(0), do: "ready"

  defp format_cooldown(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    if hours > 0, do: "#{hours}h #{minutes}m", else: "#{max(minutes, 1)}m"
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
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/master"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master tools
        </.link>
      </div>

      <.header>
        Periodic actions
        <:subtitle>Difficulties, cooldowns and the log of the actions performed.</:subtitle>
      </.header>

      <p
        :if={@actions == []}
        id="master-actions-empty"
        class="mt-6 rounded-md border border-secondary/20 p-4 text-sm text-base-content/60"
      >
        This GDR has no periodic actions: the GDR admin defines them in GM config.
      </p>

      <div :if={@action} class="mt-6 space-y-6">
        <nav id="master-action-picker" class="flex flex-wrap gap-2">
          <.link
            :for={action <- @actions}
            id={"master-action-#{action.id}"}
            patch={~p"/g/#{@current_story}/master/actions?action_id=#{action.id}"}
            class={[
              "rounded-md px-3 py-1.5 text-xs font-bold uppercase tracking-wider transition-colors",
              if(action.id == @action.id,
                do: "bg-primary/20 text-primary",
                else: "text-base-content/60 hover:text-secondary"
              )
            ]}
          >
            {action.name}
          </.link>
        </nav>

        <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            Characters
          </h2>
          <p class="mt-1 text-xs text-base-content/60">
            <%= if @action.difficulty_source == "character" do %>
              The difficulty of {@action.name} is set per character (empty: default {@action.default_difficulty}).
            <% else %>
              The difficulty of {@action.name} comes from the zone property {@action.zone_property}.
            <% end %>
            Cooldown: {@action.cooldown_hours} h.
          </p>

          <table id="master-action-characters" class="mt-3 w-full text-sm">
            <thead>
              <tr class="text-left text-xs uppercase tracking-wider text-base-content/60">
                <th class="py-1">Character</th>
                <th :if={@action.difficulty_source == "character"} class="py-1">Difficulty</th>
                <th class="py-1">Cooldown</th>
                <th></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-secondary/10">
              <tr :for={character <- @characters} id={"master-action-character-#{character.id}"}>
                <td class="py-1.5">{character.name}</td>
                <td :if={@action.difficulty_source == "character"} class="py-1.5">
                  <form
                    id={"difficulty-form-#{character.id}"}
                    phx-submit="set_difficulty"
                    class="flex items-center gap-2"
                  >
                    <input type="hidden" name="character_id" value={character.id} />
                    <input
                      type="number"
                      name="difficulty"
                      min="0"
                      max="100"
                      value={Map.get(@difficulties, character.id)}
                      placeholder={@action.default_difficulty}
                      class="input input-sm console-field w-20"
                    />
                    <button class="text-xs font-semibold text-secondary hover:text-primary">
                      Set
                    </button>
                  </form>
                </td>
                <td class="py-1.5" id={"cooldown-#{character.id}"}>
                  {format_cooldown(Map.get(@cooldowns, character.id, 0))}
                </td>
                <td class="py-1.5 text-right">
                  <button
                    :if={Map.get(@cooldowns, character.id, 0) > 0}
                    id={"reset-cooldown-#{character.id}"}
                    phx-click="reset_cooldown"
                    phx-value-character-id={character.id}
                    class="text-xs font-semibold text-secondary hover:text-primary"
                  >
                    Reset cooldown
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>

      <section :if={@actions != []} class="mt-6">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Log</h2>
        <p :if={@logs == []} id="master-action-log-empty" class="mt-2 text-sm text-base-content/60">
          No action performed yet.
        </p>
        <ul id="master-action-log" class="mt-2 space-y-2">
          <li
            :for={log <- @logs}
            id={"action-log-#{log.id}"}
            class="rounded-lg border border-secondary/20 bg-base-200/60 px-4 py-2 text-sm"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <span>
                <strong class="text-primary">{log.character.name}</strong> · {log.action.name}
                <span :if={log.location}>· {log.location.name}</span>
              </span>
              <span class="text-xs text-base-content/60">
                {Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M")} UTC
                <span :if={!log.counts_for_cooldown}>· cooldown reset</span>
              </span>
            </div>
            <p class="text-xs">
              <span class={if(log.success, do: "text-success", else: "text-error")}>
                {if log.success, do: "Success", else: "Failure"}
              </span>
              vs {log.difficulty} — {log.summary}
              <span :if={log.effect}>· {log.effect}</span>
            </p>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
