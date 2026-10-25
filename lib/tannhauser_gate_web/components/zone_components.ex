defmodule TannhauserGateWeb.ZoneComponents do
  @moduledoc "Room panels for the zone of a location and the periodic actions."
  use Phoenix.Component
  use Gettext, backend: TannhauserGateWeb.Gettext

  import TannhauserGateWeb.CoreComponents, only: [icon: 1]
  import TannhauserGateWeb.GuideComponents, only: [markdown: 1]

  attr :zone, :any, required: true
  attr :values, :list, default: []
  attr :events, :list, default: []

  @doc "The zone of the location: public properties and latest events."
  def zone_panel(assigns) do
    ~H"""
    <section id="zone-panel" class="mt-4 rounded-xl border border-mint/20 bg-ink/60 p-4">
      <h2 class="flex flex-wrap items-center gap-2 text-sm font-bold uppercase tracking-widest text-fog-300">
        <.icon name="hero-globe-europe-africa" class="size-4 text-mint" />
        <span id="zone-name">{@zone.name}</span>
        <span
          :for={{property, value} <- @values}
          id={"zone-value-#{property.slug}"}
          class="rounded bg-mint/10 px-2 py-0.5 text-[0.65rem] text-mint"
        >
          {property.name} {value}
        </span>
      </h2>

      <p :if={@zone.description} class="mt-1 text-sm text-fog-400">{@zone.description}</p>

      <details :if={@events != []} id="zone-events-panel" class="mt-3" open>
        <summary class="cursor-pointer select-none text-sm font-semibold text-mint hover:text-phosphor">
          <.icon name="hero-newspaper" class="size-4" /> {dgettext("player", "Zone events")}
        </summary>

        <ul class="mt-2 space-y-2">
          <li
            :for={event <- @events}
            id={"room-zone-event-#{event.id}"}
            class="rounded-lg border border-fog-700/50 px-3 py-2"
          >
            <p class="text-sm">
              <span class="font-semibold text-phosphor">{event.title}</span>
              <span class="ml-2 font-mono text-xs text-fog-500">
                {event.game_date_label || event.happened_on}
              </span>
            </p>
            <.markdown content={event.body} class="mt-1 text-sm" />
          </li>
        </ul>
      </details>
    </section>
    """
  end

  attr :actions, :list, required: true
  attr :characters, :list, required: true
  attr :cooldowns, :map, required: true
  attr :result, :any, default: nil

  @doc "The periodic actions the player can perform from this location."
  def actions_panel(assigns) do
    ~H"""
    <section id="room-actions" class="mt-4 rounded-xl border border-mint/20 bg-ink/60 p-4">
      <h2 class="flex items-center gap-2 text-sm font-bold uppercase tracking-widest text-fog-300">
        <.icon name="hero-bolt" class="size-4 text-mint" /> {dgettext("player", "Actions")}
      </h2>

      <div
        :if={@result}
        id="action-result"
        class={[
          "mt-3 rounded-lg border px-3 py-2 text-sm",
          if(@result.success,
            do: "border-success/40 bg-success/5 text-success",
            else: "border-error/40 bg-error/5 text-error"
          )
        ]}
      >
        <strong>{@result.character.name} · {@result.action.name}:</strong> {if @result.success,
          do: dgettext("player", "success"),
          else: dgettext("player", "failure")} {dgettext("player", "vs")} {@result.difficulty}
        <span class="text-fog-300">— {TannhauserGate.Dice.summary(@result.result)}</span>
        <span :if={@result.effect} class="text-fog-300">· {@result.effect}</span>
      </div>

      <ul class="mt-3 space-y-3">
        <li
          :for={action <- @actions}
          id={"room-action-#{action.id}"}
          class="rounded-lg border border-fog-700/50 px-3 py-2"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p class="font-semibold text-phosphor">{action.name}</p>

              <p :if={action.description} class="text-xs text-fog-400">{action.description}</p>
            </div>

            <form
              id={"perform-action-#{action.id}"}
              phx-submit="perform_action"
              class="flex items-center gap-2"
            >
              <input type="hidden" name="action_id" value={action.id} />
              <select
                :if={length(@characters) > 1}
                name="character_id"
                class="select select-sm console-field"
              >
                <option :for={character <- @characters} value={character.id}>
                  {character.name}
                </option>
              </select>

              <input
                :if={length(@characters) == 1}
                type="hidden"
                name="character_id"
                value={hd(@characters).id}
              />
              <button
                id={"perform-action-#{action.id}-button"}
                phx-disable-with={dgettext("player", "...")}
                class="btn btn-primary btn-sm console-action"
              >
                {dgettext("player", "Perform")}
              </button>
            </form>
          </div>

          <p class="mt-1 text-xs text-fog-500">
            <span
              :for={character <- @characters}
              id={"action-cooldown-#{action.id}-#{character.id}"}
              class="mr-3"
            >
              {character.name}: {format_cooldown(Map.get(@cooldowns, {action.id, character.id}, 0))}
            </span>
          </p>
        </li>
      </ul>
    </section>
    """
  end

  @doc "A human readable remaining cooldown."
  def format_cooldown(0), do: dgettext("player", "ready")

  def format_cooldown(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if hours > 0,
      do: dgettext("player", "ready in %{hours}h %{minutes}m", hours: hours, minutes: minutes),
      else: dgettext("player", "ready in %{value}m", value: max(minutes, 1))
  end
end
