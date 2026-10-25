defmodule TannhauserGateWeb.MasterLive.Calendar do
  @moduledoc """
  Masters see the current in-game date (calendar module) and can move the
  clock: the date they set becomes "now" and the clock keeps running from
  there at the GDR speed.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Calendar, as: GameCalendar
  alias TannhauserGate.Calendars

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :calendar}}
  on_mount {TannhauserGateWeb.UserAuth, {:require_permission, :can_manage_world}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, dgettext("management", "Game calendar")) |> load()}
  end

  defp story(socket), do: socket.assigns.current_story

  defp load(socket) do
    saved = Calendars.get_calendar(story(socket))
    config = saved || Calendars.default_config(story(socket))
    form_config = Calendars.form_config(config)

    socket
    |> assign(:saved, saved)
    |> assign(:config, form_config)
    |> assign(:form, to_form(Calendars.change_date(form_config), as: :date))
  end

  @impl true
  def handle_event("validate", %{"date" => params}, socket) do
    changeset =
      socket.assigns.config |> Calendars.change_date(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :date))}
  end

  def handle_event("set_now", %{"date" => params}, socket) do
    case Calendars.set_now(story(socket), params) do
      {:ok, config} ->
        label = config |> GameCalendar.to_game() |> GameCalendar.format()

        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("management", "The game clock now reads %{label}.", label: label)
         )
         |> update(:current_story, &%{&1 | calendar: config})
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :date))}
    end
  end

  defp month_options(config) do
    config.month_names
    |> Enum.with_index(1)
    |> Enum.map(fn {name, index} -> {"#{index}. #{name}", index} end)
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
        {dgettext("management", "Game calendar")}
        <:subtitle>
          {dgettext("management", "The in-game date and time of %{current_story_name}.",
            current_story_name: @current_story.name
          )}
        </:subtitle>
      </.header>

      <div class="mt-6 grid gap-6 lg:grid-cols-[22rem_1fr]">
        <section
          id="master-calendar-now"
          class="rounded-xl border border-primary/30 bg-base-200/80 p-5"
        >
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("management", "Now in game")}
          </h2>

          <p class="mt-3 text-lg font-semibold text-primary">
            <.game_clock :if={@saved} id="master-calendar-clock" calendar={@saved} />
            <span :if={!@saved} id="master-calendar-unset" class="text-sm text-warning">
              {dgettext(
                "management",
                "The GDR admin has not set up the calendar yet: setting a date starts a real-world-like calendar."
              )}
            </span>
          </p>

          <p :if={@saved} class="mt-2 text-xs text-base-content/60">
            {dgettext(
              "management",
              "Speed ×%{saved_ratio} · %{length__saved_month_names} months a year",
              saved_ratio: @saved.ratio,
              length__saved_month_names: length(@saved.month_names)
            )}
          </p>
        </section>

        <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {dgettext("management", "Move the clock")}
          </h2>

          <p class="mt-1 text-xs text-base-content/60">
            {dgettext("management", "The date you set becomes the current one for everybody.")}
          </p>

          <.form
            for={@form}
            id="calendar-date-form"
            phx-change="validate"
            phx-submit="set_now"
            class="mt-4"
          >
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-5">
              <.input field={@form[:epoch_year]} type="number" label={dgettext("management", "Year")} />
              <.input
                field={@form[:epoch_month]}
                type="select"
                label={dgettext("management", "Month")}
                options={month_options(@config)}
              />
              <.input
                field={@form[:epoch_day]}
                type="number"
                min="1"
                label={dgettext("management", "Day")}
              />
              <.input
                field={@form[:epoch_hour]}
                type="number"
                min="0"
                max="23"
                label={dgettext("management", "Hour")}
              />
              <.input
                field={@form[:epoch_minute]}
                type="number"
                min="0"
                max="59"
                label={dgettext("management", "Minute")}
              />
            </div>

            <.button id="set-game-date" phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Set the date"
            )}</.button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
