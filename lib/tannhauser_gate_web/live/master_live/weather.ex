defmodule TannhauserGateWeb.MasterLive.Weather do
  @moduledoc """
  Masters set the current weather of each zone by hand (kept for one weather
  interval before the roller replaces it), roll it now from the weather table
  or clear it.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Calendars, Weather, Zones}
  alias TannhauserGate.Weather.{Condition, ZoneWeather}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :weather}}
  on_mount {TannhauserGateWeb.UserAuth, {:require_permission, :can_manage_world}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    if connected?(socket), do: Weather.subscribe(story.id)

    {:ok,
     socket
     |> assign(:page_title, "Weather")
     |> assign(:zones, Zones.list_zones(story))
     |> assign(:conditions, Weather.list_conditions(story))
     |> assign(:season, Calendars.current_season(story))
     |> reload()
     |> reset_form()}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket), do: assign(socket, :weathers, Weather.zone_weathers(story(socket)))

  defp reset_form(socket, params \\ %{}) do
    form =
      %ZoneWeather{}
      |> Weather.change_zone_weather(params)
      |> to_form(as: :weather)

    socket
    |> assign(:form, form)
    |> assign(:zone_id, params["zone_id"])
    |> assign(:preset, params["preset"])
  end

  @impl true
  def handle_info({:weather_changed, _story_id}, socket), do: {:noreply, reload(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"weather" => params} = all, socket) do
    params = maybe_preset(params, all["_target"], socket.assigns.conditions)

    changeset =
      %ZoneWeather{}
      |> Weather.change_zone_weather(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :weather))
     |> assign(:zone_id, params["zone_id"])
     |> assign(:preset, params["preset"])}
  end

  def handle_event("set", %{"weather" => params}, socket) do
    case Weather.set_zone_weather(
           story(socket),
           params["zone_id"],
           socket.assigns.current_user,
           params
         ) do
      {:ok, _weather} ->
        {:noreply, socket |> put_flash(:info, "Weather set.") |> reload() |> reset_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :form, to_form(Map.put(changeset, :action, :insert), as: :weather))}

      {:error, :zone_not_found} ->
        {:noreply, put_flash(socket, :error, "Choose a zone.")}
    end
  end

  def handle_event("roll", %{"zone" => zone_id}, socket) do
    case Weather.roll_zone(story(socket), zone_id) do
      {:ok, weather} ->
        {:noreply, socket |> put_flash(:info, "Rolled: #{weather.condition}.") |> reload()}

      {:error, :empty_table} ->
        {:noreply,
         put_flash(socket, :error, "The weather table has no condition for this season.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That zone does not exist in this GDR.")}
    end
  end

  def handle_event("clear", %{"zone" => zone_id}, socket) do
    case Weather.clear_zone_weather(story(socket), zone_id) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Weather cleared.") |> reload()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That zone does not exist in this GDR.")}
    end
  end

  # Picking a condition of the table fills the condition, icon and description.
  defp maybe_preset(params, ["weather", "preset"], conditions) do
    case Enum.find(conditions, &(to_string(&1.id) == params["preset"])) do
      nil ->
        params

      condition ->
        Map.merge(params, %{
          "condition" => condition.name,
          "icon" => condition.icon,
          "description" => condition.description || ""
        })
    end
  end

  defp maybe_preset(params, _target, _conditions), do: params

  defp source_label(%ZoneWeather{} = weather) do
    who = if weather.set_by == "master", do: "Set by a master", else: "Rolled"
    "#{who} · #{when_label(weather.set_at)} · until #{when_label(weather.expires_at)}"
  end

  defp when_label(%DateTime{} = at), do: Calendar.strftime(at, "%d/%m %H:%M UTC")

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
        Weather
        <:subtitle>
          The sky over the zones of {@current_story.name}. Season: <strong>{@season}</strong>
          · new weather every {@current_story.weather_interval_hours}h.
        </:subtitle>
      </.header>

      <p
        :if={@zones == []}
        id="master-weather-empty"
        class="mt-6 rounded-md border border-secondary/20 p-4 text-sm text-base-content/60"
      >
        This GDR has no zones yet: the GDR admin defines them in GM config.
      </p>

      <div :if={@zones != []} class="mt-6 grid gap-6 lg:grid-cols-[1fr_22rem]">
        <section id="master-weather-zones" class="space-y-3">
          <article
            :for={zone <- @zones}
            id={"master-weather-zone-#{zone.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4 transition hover:border-secondary/40"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="font-semibold text-primary">{zone.name}</h3>
                <div class="mt-1 flex flex-wrap items-center gap-2 text-xs text-base-content/60">
                  <.weather_badge id={"zone-weather-#{zone.id}"} weather={@weathers[zone.id]} />
                  <span :if={!@weathers[zone.id]}>No weather yet.</span>
                  <span :if={@weathers[zone.id]} id={"zone-weather-source-#{zone.id}"}>
                    {source_label(@weathers[zone.id])}
                  </span>
                </div>
                <p
                  :if={@weathers[zone.id] && @weathers[zone.id].description}
                  class="mt-1 text-xs italic text-base-content/60"
                >
                  {@weathers[zone.id].description}
                </p>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  :if={@conditions != []}
                  id={"roll-weather-#{zone.id}"}
                  phx-click="roll"
                  phx-value-zone={zone.id}
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-primary"
                  title="Roll from the table"
                >
                  <.icon name="hero-arrow-path" class="size-4" />
                </button>
                <button
                  :if={@weathers[zone.id]}
                  id={"clear-weather-#{zone.id}"}
                  phx-click="clear"
                  phx-value-zone={zone.id}
                  data-confirm="Clear the weather of this zone?"
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-error"
                  title="Clear"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </div>
          </article>
        </section>

        <section class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Set the weather</h2>
          <.form
            for={@form}
            id="zone-weather-form"
            phx-change="validate"
            phx-submit="set"
            class="mt-4"
          >
            <.input
              name="weather[zone_id]"
              id="zone-weather-zone"
              type="select"
              label="Zone"
              prompt="Choose a zone"
              options={Enum.map(@zones, &{&1.name, &1.id})}
              value={@zone_id}
            />
            <.input
              :if={@conditions != []}
              name="weather[preset]"
              id="zone-weather-preset"
              type="select"
              label="From the table (optional)"
              prompt="Custom"
              options={Enum.map(@conditions, &{&1.name, &1.id})}
              value={@preset}
            />
            <.input field={@form[:condition]} type="text" label="Condition" required />
            <div class="grid grid-cols-2 gap-3">
              <.input field={@form[:icon]} type="select" label="Icon" options={Condition.icons()} />
              <.input field={@form[:temperature]} type="number" label="Temperature °C" />
            </div>
            <.input field={@form[:description]} type="text" label="Description (optional)" />
            <.button id="set-zone-weather" phx-disable-with="Saving...">Set weather</.button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
