defmodule TannhauserGateWeb.CalendarComponents do
  @moduledoc """
  Components for the calendar and weather modules: the running game clock
  and the zone weather badge.

  The weather icons (`TannhauserGate.Weather.Condition.icons/0`), listed here
  so Tailwind generates them: hero-sun hero-moon hero-cloud
  hero-cloud-arrow-down hero-bolt hero-eye-slash hero-beaker hero-fire
  hero-sparkles hero-globe-alt hero-signal-slash hero-exclamation-triangle.
  """
  use Phoenix.Component

  import TannhauserGateWeb.CoreComponents, only: [icon: 1]

  alias TannhauserGate.Calendar, as: GameCalendar
  alias TannhauserGate.Calendar.Config

  @doc """
  The game date and time of `calendar` (a `TannhauserGate.Calendar.Config`),
  rendered on the server and then advanced in the browser by the `.GameClock`
  hook with the same math as `TannhauserGate.Calendar` (no server tick).
  Renders nothing without a calendar.
  """
  attr :id, :string, required: true
  attr :calendar, :any, required: true
  attr :style, :atom, default: :full, values: [:full, :date, :time]
  attr :class, :any, default: nil

  def game_clock(%{calendar: %Config{} = config} = assigns) do
    assigns =
      assign(assigns,
        text: config |> GameCalendar.to_game() |> GameCalendar.format(assigns.style),
        epoch: DateTime.to_unix(config.epoch_real),
        epoch_minutes: GameCalendar.epoch_minutes(config)
      )

    ~H"""
    <span class={["inline-flex items-center gap-1.5", @class]} title="In-game date and time">
      <.icon name="hero-calendar-days" class="size-3.5 shrink-0 opacity-80" />
      <time
        id={@id}
        phx-hook=".GameClock"
        phx-update="ignore"
        data-epoch={@epoch}
        data-epoch-minutes={@epoch_minutes}
        data-ratio={@calendar.ratio}
        data-months={Jason.encode!(@calendar.month_names)}
        data-days={Jason.encode!(@calendar.days_per_month)}
        data-weekdays={Jason.encode!(@calendar.weekday_names)}
        data-era={@calendar.year_suffix}
        data-style={@style}
        class="tabular-nums"
      >{@text}</time>
    </span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".GameClock">
      // Advances the game clock locally: same math as TannhauserGate.Calendar.
      const mod = (a, n) => ((a % n) + n) % n
      const pad = n => String(n).padStart(2, "0")

      export default {
        mounted() {
          this.render()
          this.schedule()
        },
        updated() {
          this.render()
        },
        destroyed() {
          clearTimeout(this.timer)
        },
        schedule() {
          const ratio = Number(this.el.dataset.ratio) || 1
          const ms = Math.max(1000, Math.min(20000, 60000 / ratio / 2))
          this.timer = setTimeout(() => {
            this.render()
            this.schedule()
          }, ms)
        },
        render() {
          const d = this.el.dataset
          const months = JSON.parse(d.months || "[]")
          const days = JSON.parse(d.days || "[]")
          const weekdays = JSON.parse(d.weekdays || "[]")
          if (days.length === 0) return
          const elapsed = Math.floor(Date.now() / 1000) - Number(d.epoch)
          const minutes = Number(d.epochMinutes) + Math.floor((elapsed * Number(d.ratio)) / 60)
          const perYear = Math.max(days.reduce((a, b) => a + b, 0), 1)
          const absDay = Math.floor(minutes / 1440)
          const minuteOfDay = mod(minutes, 1440)
          const year = Math.floor(absDay / perYear)
          let day = mod(absDay, perYear)
          let month = 0
          while (month < days.length - 1 && day >= days[month]) {
            day -= days[month]
            month++
          }
          const time = `${pad(Math.floor(minuteOfDay / 60))}:${pad(minuteOfDay % 60)}`
          const date = `${day + 1} ${months[month]} ${year}${d.era ? " " + d.era : ""}`
          const weekday = weekdays.length ? `${weekdays[mod(absDay, weekdays.length)]}, ` : ""
          const text =
            d.style === "time" ? time : d.style === "date" ? date : `${weekday}${date} · ${time}`
          if (this.el.textContent !== text) this.el.textContent = text
        },
      }
    </script>
    """
  end

  def game_clock(assigns), do: ~H""

  @doc "The weather of a zone (a `TannhauserGate.Weather.ZoneWeather`) as a compact badge."
  attr :id, :string, required: true
  attr :weather, :any, required: true
  attr :class, :any, default: nil

  def weather_badge(%{weather: %{condition: _}} = assigns) do
    ~H"""
    <span
      id={@id}
      title={@weather.description || @weather.condition}
      class={[
        "inline-flex items-center gap-1.5 rounded border border-info/40 bg-info/10 px-2 py-0.5 text-xs font-semibold text-info transition-colors hover:border-info/70 hover:bg-info/15",
        @class
      ]}
    >
      <.icon name={@weather.icon} class="size-3.5 shrink-0" />
      <span>{@weather.condition}</span>
      <span :if={@weather.temperature} class="tabular-nums opacity-80">
        {@weather.temperature}°C
      </span>
    </span>
    """
  end

  def weather_badge(assigns), do: ~H""
end
