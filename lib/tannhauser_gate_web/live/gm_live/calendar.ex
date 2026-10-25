defmodule TannhauserGateWeb.GmLive.Calendar do
  @moduledoc """
  GM config for the calendar module: the months (names, lengths, seasons),
  the weekdays, the era label, the time ratio and the current game date the
  clock is re-anchored to on save.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.Calendar, as: GameCalendar
  alias TannhauserGate.Calendars

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :calendar}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "GM dashboard")
     |> load()}
  end

  defp story(socket), do: socket.assigns.current_story

  defp load(socket) do
    saved = Calendars.get_calendar(story(socket))
    config = Calendars.form_config(saved || Calendars.default_config(story(socket)))

    socket
    |> assign(:saved, saved)
    |> assign(:config, config)
    |> assign(:form, to_form(Calendars.change_calendar(config)))
  end

  @impl true
  def handle_event("validate", %{"config" => params}, socket) do
    changeset =
      socket.assigns.config |> Calendars.change_calendar(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"config" => params}, socket) do
    case Calendars.save_calendar(story(socket), params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> put_flash(:info, "Calendar saved: the clock now runs from the date you set.")
         |> update(:current_story, &%{&1 | calendar: config})
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp month_options(form) do
    names = Ecto.Changeset.get_field(form.source, :month_names) || []
    names |> Enum.with_index(1) |> Enum.map(fn {name, index} -> {"#{index}. #{name}", index} end)
  end

  defp preview(form) do
    changeset = form.source

    if changeset.valid? do
      config = Ecto.Changeset.apply_changes(changeset)

      config
      |> Map.put(:epoch_real, DateTime.utc_now())
      |> GameCalendar.to_game()
      |> GameCalendar.format()
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
      my_characters={@my_characters}
      active_character={@active_character}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <.gm_header story={@current_story} />
      <.gm_tabs story={@current_story} tab="calendar" />

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_22rem]">
        <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Game calendar</h2>
          <p :if={!@saved} id="calendar-unsaved" class="mt-2 text-xs text-warning">
            Not saved yet: the clock shows once you save a calendar.
          </p>
          <.form
            for={@form}
            id="calendar-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4"
          >
            <.input
              field={@form[:months_text]}
              type="textarea"
              label="Months: one per line, “Name | days | season”"
              rows="12"
            />
            <.input
              field={@form[:weekdays_text]}
              type="text"
              label="Weekdays (comma-separated, optional)"
            />
            <div class="grid gap-3 sm:grid-cols-2">
              <.input
                field={@form[:ratio]}
                type="number"
                min="1"
                max="1000"
                label="Speed (game seconds per real second)"
              />
              <.input field={@form[:year_suffix]} type="text" label="Era label (e.g. AE)" />
            </div>

            <h3 class="mt-4 text-xs font-bold uppercase tracking-[0.2em] text-secondary">
              Current game date
            </h3>
            <p class="mt-1 text-xs text-base-content/60">
              Saving re-anchors the clock: right now it will be this date and time.
            </p>
            <div class="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-5">
              <.input field={@form[:epoch_year]} type="number" label="Year" />
              <.input
                field={@form[:epoch_month]}
                type="select"
                label="Month"
                options={month_options(@form)}
              />
              <.input field={@form[:epoch_day]} type="number" min="1" label="Day" />
              <.input field={@form[:epoch_hour]} type="number" min="0" max="23" label="Hour" />
              <.input field={@form[:epoch_minute]} type="number" min="0" max="59" label="Minute" />
            </div>

            <.button id="save-calendar" phx-disable-with="Saving...">Save calendar</.button>
          </.form>
        </section>

        <aside class="space-y-4">
          <section class="rounded-xl border border-primary/30 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Now in game</h2>
            <p id="calendar-current" class="mt-3 font-semibold text-primary">
              <.game_clock :if={@saved} id="gm-calendar-clock" calendar={@saved} />
              <span :if={!@saved}>—</span>
            </p>
            <p class="mt-4 text-xs uppercase tracking-wider text-base-content/50">After saving</p>
            <p id="calendar-preview" class="mt-1 text-sm">
              {preview(@form) || "Fix the errors to see a preview."}
            </p>
          </section>
          <section class="rounded-xl border border-secondary/20 bg-base-200/60 p-5 text-sm text-base-content/70">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">How it works</h2>
            <ul class="mt-2 list-disc space-y-1 pl-4">
              <li>The number of lines sets the months in a year; days default to 30.</li>
              <li>Seasons drive the weather table when the weather module is on.</li>
              <li>A speed of 4 makes a game day last 6 real hours.</li>
              <li>Masters can move the clock from the master tools.</li>
            </ul>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
