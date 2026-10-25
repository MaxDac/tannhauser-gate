defmodule TannhauserGateWeb.MasterLive.Actions do
  @moduledoc """
  Masters manage the periodic actions: per-character difficulty (for the
  actions whose difficulty is set per character), cooldown resets and the
  log of performed actions.
  """
  use TannhauserGateWeb, :live_view

  on_mount {TannhauserGateWeb.UserAuth, {:require_permission, :can_manage_world}}

  alias TannhauserGate.{Characters, PeriodicActions}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, dgettext("management", "Periodic actions"))
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
         socket
         |> put_flash(
           :info,
           dgettext("management", "Difficulty of %{character_name} saved.",
             character_name: character.name
           )
         )
         |> load_action()}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("management", "The difficulty must be between 0 and 100.")
         )}
    end
  end

  def handle_event("reset_cooldown", %{"character-id" => id}, socket) do
    character = find_character(socket, id)
    {:ok, _} = PeriodicActions.reset_cooldown(socket.assigns.action, character)

    {:noreply,
     socket
     |> put_flash(
       :info,
       dgettext("management", "Cooldown of %{character_name} reset.",
         character_name: character.name
       )
     )
     |> load_action()}
  end

  defp find_character(socket, id) do
    id = if is_binary(id), do: String.to_integer(id), else: id

    Enum.find(socket.assigns.characters, &(&1.id == id)) ||
      raise Ecto.NoResultsError, queryable: Characters
  end

  defp action_summary(log) do
    if Gettext.get_locale(TannhauserGateWeb.Gettext) == "en" do
      log.summary
    else
      TannhauserGate.Dice.summary(log.result)
    end
  end

  defp format_cooldown(0), do: dgettext("management", "ready")

  defp format_cooldown(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if hours > 0,
      do: dgettext("management", "%{hours}h %{minutes}m", hours: hours, minutes: minutes),
      else: "#{max(minutes, 1)}m"
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
      my_characters={@my_characters}
      active_character={@active_character}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/master"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> {dgettext(
            "management",
            "Master tools"
          )}
        </.link>
      </div>

      <.header>
        {dgettext("management", "Periodic actions")}
        <:subtitle>
          {dgettext("management", "Difficulties, cooldowns and the log of the actions performed.")}
        </:subtitle>
      </.header>

      <p
        :if={@actions == []}
        id="master-actions-empty"
        class="mt-6 rounded-md border border-secondary/20 p-4 text-sm text-base-content/60"
      >
        {dgettext(
          "management",
          "This GDR has no periodic actions: the GDR admin defines them in GM config."
        )}
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
            {dgettext("management", "Characters")}
          </h2>

          <p class="mt-1 text-xs text-base-content/60">
            <%= if @action.difficulty_source == "character" do %>
              {dgettext(
                "management",
                "The difficulty of %{action_name} is set per character (empty: default %{action_default_difficulty}).",
                action_name: @action.name,
                action_default_difficulty: @action.default_difficulty
              )}
            <% else %>
              {dgettext(
                "management",
                "The difficulty of %{action_name} comes from the zone property %{action_zone_property}.",
                action_name: @action.name,
                action_zone_property: @action.zone_property
              )}
            <% end %>
            {dgettext("management", "Cooldown: %{action_cooldown_hours} h.",
              action_cooldown_hours: @action.cooldown_hours
            )}
          </p>

          <table id="master-action-characters" class="mt-3 w-full text-sm">
            <thead>
              <tr class="text-left text-xs uppercase tracking-wider text-base-content/60">
                <th class="py-1">{dgettext("management", "Character")}</th>

                <th :if={@action.difficulty_source == "character"} class="py-1">
                  {dgettext("management", "Difficulty")}
                </th>

                <th class="py-1">{dgettext("management", "Cooldown")}</th>

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
                      {dgettext("management", "Set")}
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
                    {dgettext("management", "Reset cooldown")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>

      <section :if={@actions != []} class="mt-6">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Log")}
        </h2>

        <p :if={@logs == []} id="master-action-log-empty" class="mt-2 text-sm text-base-content/60">
          {dgettext("management", "No action performed yet.")}
        </p>

        <ul id="master-action-log" class="mt-2 space-y-2">
          <li
            :for={log <- @logs}
            id={"action-log-#{log.id}"}
            class="rounded-lg border border-secondary/20 bg-base-200/60 px-4 py-2 text-sm"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <span>
                <strong class="text-primary">{log.character.name}</strong>
                · {log.action.name} <span :if={log.location}>· {log.location.name}</span>
              </span>

              <span class="text-xs text-base-content/60">
                {dgettext("management", "%{value} UTC",
                  value: Calendar.strftime(log.inserted_at, "%Y-%m-%d %H:%M")
                )}
                <span :if={!log.counts_for_cooldown}>{dgettext("management", "· cooldown reset")}</span>
              </span>
            </div>

            <p class="text-xs">
              <span class={if(log.success, do: "text-success", else: "text-error")}>
                {if log.success,
                  do: dgettext("management", "Success"),
                  else: dgettext("management", "Failure")}
              </span>
              {dgettext("management", "vs %{log_difficulty} — %{log_summary}",
                log_difficulty: log.difficulty,
                log_summary: action_summary(log)
              )} <span :if={log.effect}>· {log.effect}</span>
            </p>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
