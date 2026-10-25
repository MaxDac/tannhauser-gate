defmodule TannhauserGateWeb.GmLive.Actions do
  @moduledoc """
  GM config: the GDR admin defines the periodic (hunt-like) actions: dice
  pool, difficulty source, tracker effects and cooldown.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.{PeriodicActions, Sheet, Trackers, Zones}
  alias TannhauserGate.PeriodicActions.Action

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    trackers = Trackers.list_trackers(story)

    {:ok,
     socket
     |> assign(:page_title, dgettext("management", "GM dashboard"))
     |> assign(:items, Sheet.list_items(story))
     |> assign(:trackers, trackers)
     |> assign(:damage_types, trackers |> Enum.flat_map(& &1.damage_types) |> Enum.uniq())
     |> assign(:properties, Zones.list_properties(story))
     |> reload()
     |> edit_action(new_action(story))}
  end

  defp new_action(story), do: %Action{story_id: story.id}

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket), do: assign(socket, :actions, PeriodicActions.list_actions(story(socket)))

  defp edit_action(socket, action) do
    assign(socket, action: action, form: to_form(PeriodicActions.change_action(action)))
  end

  @impl true
  def handle_event("validate", %{"action" => params}, socket) do
    changeset =
      socket.assigns.action
      |> PeriodicActions.change_action(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"action" => params}, socket) do
    result =
      case socket.assigns.action do
        %Action{id: nil} -> PeriodicActions.create_action(story(socket), params)
        action -> PeriodicActions.update_action(action, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("management", "Periodic action saved."))
         |> reload()
         |> edit_action(new_action(story(socket)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket),
    do: {:noreply, edit_action(socket, PeriodicActions.get_action!(story(socket), id))}

  def handle_event("cancel", _, socket),
    do: {:noreply, edit_action(socket, new_action(story(socket)))}

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> PeriodicActions.get_action!(id) |> PeriodicActions.delete_action()

    {:noreply,
     socket
     |> put_flash(:info, dgettext("management", "Periodic action deleted."))
     |> reload()
     |> edit_action(new_action(story(socket)))}
  end

  defp effect_label(nil, _type, _delta), do: dgettext("management", "nothing")
  defp effect_label(_tracker, _type, 0), do: dgettext("management", "nothing")

  defp effect_label(tracker, type, delta) do
    sign = if delta > 0, do: "+", else: ""
    Enum.join(Enum.reject([tracker, "#{sign}#{delta}", type], &is_nil/1), " ")
  end

  defp difficulty_label(%Action{difficulty_source: "zone"} = action),
    do:
      dgettext(
        "management",
        "zone %{action_zone_property} (default %{action_default_difficulty})",
        action_zone_property: action.zone_property,
        action_default_difficulty: action.default_difficulty
      )

  defp difficulty_label(action),
    do:
      dgettext("management", "per character (default %{action_default_difficulty})",
        action_default_difficulty: action.default_difficulty
      )

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
      <.gm_header story={@current_story} /> <.gm_tabs story={@current_story} tab="actions" />
      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_24rem]">
        <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {if @action.id,
              do: dgettext("management", "Edit periodic action"),
              else: dgettext("management", "New periodic action")}
          </h2>

          <p class="mt-1 text-sm text-base-content/70">
            {dgettext(
              "management",
              "Characters perform periodic actions (e.g. a hunt) from a location: the dice pool is rolled against the difficulty and the tracker effect is applied. Masters see the log."
            )}
          </p>

          <.form
            for={@form}
            id="periodic-action-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4"
          >
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@form[:name]}
                type="text"
                label={dgettext("management", "Name")}
                required
              />
              <.input
                field={@form[:cooldown_hours]}
                type="number"
                label={dgettext("management", "Cooldown (hours)")}
                min="0"
              />
            </div>

            <.input
              field={@form[:description]}
              type="textarea"
              label={dgettext("management", "Description")}
              rows="2"
            /> <input type="hidden" name="action[items][]" value="" />
            <.input
              field={@form[:items]}
              type="select"
              multiple
              label={dgettext("management", "Dice pool (sheet items)")}
              options={Enum.map(@items, &{&1.name, &1.slug})}
              size="6"
            />
            <fieldset class="mt-2 rounded-lg border border-secondary/20 p-3">
              <legend class="px-1 text-xs font-bold uppercase tracking-wider text-secondary">
                {dgettext("management", "Difficulty")}
              </legend>

              <div class="grid gap-3 sm:grid-cols-3">
                <.input
                  field={@form[:difficulty_source]}
                  type="select"
                  label={dgettext("management", "Source")}
                  options={[
                    {dgettext("management", "Zone property"), "zone"},
                    {dgettext("management", "Per character (masters)"), "character"}
                  ]}
                />
                <.input
                  :if={@form[:difficulty_source].value in ["zone", nil]}
                  field={@form[:zone_property]}
                  type="select"
                  label={dgettext("management", "Zone property")}
                  prompt={dgettext("management", "Choose a property")}
                  options={Enum.map(@properties, &{&1.name, &1.slug})}
                />
                <.input
                  field={@form[:default_difficulty]}
                  type="number"
                  label={dgettext("management", "Default")}
                  min="0"
                />
              </div>

              <p :if={@properties == []} class="text-xs text-warning">
                {dgettext(
                  "management",
                  "Define zone properties in the Zones tab to use them as difficulty."
                )}
              </p>
            </fieldset>

            <fieldset
              :for={
                {kind, label} <- [
                  {"success", dgettext("management", "On success")},
                  {"failure", dgettext("management", "On failure")}
                ]
              }
              id={"#{kind}-effect"}
              class="mt-3 rounded-lg border border-secondary/20 p-3"
            >
              <legend class="px-1 text-xs font-bold uppercase tracking-wider text-secondary">
                {label}
              </legend>

              <div class="grid gap-3 sm:grid-cols-3">
                <.input
                  field={@form[:"#{kind}_tracker"]}
                  type="select"
                  label={dgettext("management", "Tracker")}
                  prompt={dgettext("management", "No effect")}
                  options={Enum.map(@trackers, &{&1.name, &1.slug})}
                />
                <.input
                  field={@form[:"#{kind}_damage_type"]}
                  type="select"
                  label={dgettext("management", "Damage type")}
                  prompt={dgettext("management", "—")}
                  options={@damage_types}
                />
                <.input
                  field={@form[:"#{kind}_delta"]}
                  type="number"
                  label={dgettext("management", "Change")}
                />
              </div>
            </fieldset>

            <.input
              field={@form[:position]}
              type="number"
              label={dgettext("management", "Position")}
              min="0"
            />
            <div class="flex gap-2">
              <.button
                id="save-periodic-action"
                phx-disable-with={dgettext("management", "Saving...")}
              >
                {if @action.id,
                  do: dgettext("management", "Update action"),
                  else: dgettext("management", "Add action")}
              </.button>

              <.button :if={@action.id} type="button" id="cancel-periodic-action" phx-click="cancel">
                {dgettext("management", "Cancel")}
              </.button>
            </div>
          </.form>
        </section>

        <section id="periodic-actions" class="space-y-3">
          <p :if={@actions == []} id="periodic-actions-empty" class="text-sm text-base-content/60">
            {dgettext("management", "No periodic actions yet.")}
          </p>

          <div
            :for={action <- @actions}
            id={"periodic-action-#{action.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4"
          >
            <div class="flex items-center justify-between">
              <h3 class="font-semibold text-primary">{action.name}</h3>

              <div class="flex gap-1">
                <button
                  id={"edit-periodic-action-#{action.id}"}
                  phx-click="edit"
                  phx-value-id={action.id}
                  class="rounded p-1 text-base-content/60 hover:text-secondary"
                  title={dgettext("management", "Edit")}
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>

                <button
                  id={"delete-periodic-action-#{action.id}"}
                  phx-click="delete"
                  phx-value-id={action.id}
                  data-confirm={dgettext("management", "Delete this action and its log?")}
                  class="rounded p-1 text-base-content/60 hover:text-error"
                  title={dgettext("management", "Delete")}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>

            <dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
              <dt class="text-base-content/60">{dgettext("management", "Pool")}</dt>

              <dd>{Enum.join(action.items, " + ")}</dd>

              <dt class="text-base-content/60">{dgettext("management", "Difficulty")}</dt>

              <dd>{difficulty_label(action)}</dd>

              <dt class="text-base-content/60">{dgettext("management", "Success")}</dt>

              <dd>
                {effect_label(
                  action.success_tracker,
                  action.success_damage_type,
                  action.success_delta
                )}
              </dd>

              <dt class="text-base-content/60">{dgettext("management", "Failure")}</dt>

              <dd>
                {effect_label(
                  action.failure_tracker,
                  action.failure_damage_type,
                  action.failure_delta
                )}
              </dd>

              <dt class="text-base-content/60">{dgettext("management", "Cooldown")}</dt>

              <dd>
                {dgettext("management", "%{action_cooldown_hours} h",
                  action_cooldown_hours: action.cooldown_hours
                )}
              </dd>
            </dl>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
