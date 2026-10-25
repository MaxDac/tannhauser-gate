defmodule TannhauserGateWeb.MapLive do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Bookings, Chat, Guilds, Stories, Weather, Zones}
  alias TannhauserGateWeb.MapPins

  @impl true
  def mount(_params, _session, socket) do
    story = Stories.get_story!(socket.assigns.current_story.id)
    # Stable numbering for the pins and the legend.
    story = %{story | locations: Enum.sort_by(story.locations, & &1.id)}
    weather? = Weather.enabled?(story)
    if weather? and connected?(socket), do: Weather.subscribe(story.id)

    {:ok,
     socket
     |> assign(:story, story)
     |> assign(:pins, MapPins.layout(story.locations, story.map_width, story.map_height))
     |> assign(:weather?, weather?)
     |> assign(:zones, if(weather?, do: Zones.list_zones(story), else: []))
     |> load_weather()
     |> assign(:counts, Chat.count_messages_by_location())
     |> assign(:bookings, Bookings.upcoming_by_location(story.id))
     |> assign(:guild_names, guild_names(socket.assigns.current_user, story))
     |> assign(:page_title, dgettext("player", "%{name} · Map", name: story.name))}
  end

  defp load_weather(%{assigns: %{weather?: true, story: story}} = socket),
    do: assign(socket, :weathers, Weather.zone_weathers(story))

  defp load_weather(socket), do: assign(socket, :weathers, %{})

  @impl true
  def handle_info({:weather_changed, _story_id}, socket), do: {:noreply, load_weather(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("enter_room", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/g/#{socket.assigns.current_story}/rooms/#{id}")}
  end

  # Names of the guilds rooms are reserved to, hidden for secret guilds the
  # user cannot see (guilds module).
  defp guild_names(user, story) do
    if Guilds.enabled?(story) do
      Map.new(Guilds.list_guilds(story), fn guild ->
        {guild.id,
         if(Guilds.visible?(user, story, guild),
           do: guild.name,
           else: dgettext("player", "Guild members only")
         )}
      end)
    else
      %{}
    end
  end

  defp booking_line([]), do: dgettext("player", "Private: free to book.")

  defp booking_line([booking | rest]) do
    now = DateTime.utc_now()
    who = booking.character.name

    more =
      if rest == [], do: "", else: dgettext("player", " (+%{value} more)", value: length(rest))

    if DateTime.compare(booking.starts_at, now) == :gt,
      do:
        dgettext("player", "Next booking: %{who}, %{value} UTC%{more}",
          who: who,
          value: format_local_date(booking.starts_at, "%d %b %H:%M"),
          more: more
        ),
      else:
        dgettext("player", "Booked by %{who} until %{value} UTC%{more}",
          who: who,
          value: Calendar.strftime(booking.ends_at, "%H:%M"),
          more: more
        )
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
      <.header>
        {@story.name}
        <:subtitle>{@story.summary}</:subtitle>
      </.header>

      <div class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_20rem]">
        <div
          id="map-frame"
          class="map-frame relative self-start overflow-hidden rounded-xl border border-mint/30 bg-night shadow-phosphor"
        >
          <svg
            id="city-map"
            viewBox={"0 0 #{@story.map_width} #{@story.map_height}"}
            class="block h-auto w-full"
            role="img"
            aria-label={dgettext("player", "Map of %{name}", name: @story.name)}
          >
            <image
              :if={@story.map_svg not in [nil, ""]}
              id="map-artwork"
              href={Stories.map_artwork_src(@story)}
              width={@story.map_width}
              height={@story.map_height}
            />
            <g :for={location <- @story.locations} class="map-room">
              <polygon
                id={"room-area-#{location.id}"}
                points={location.area}
                fill={location.color}
                stroke={location.color}
                data-location-name={location.name}
                phx-click="enter_room"
                phx-value-id={location.id}
              >
                <title>{location.name}</title>
              </polygon>
            </g>
          </svg>

          <nav
            id="map-pins"
            aria-label={dgettext("player", "Locations of %{name}", name: @story.name)}
            class="absolute inset-0"
          >
            <.link
              :for={%{location: location, index: index} = pin <- @pins}
              id={"room-pin-#{location.id}"}
              navigate={~p"/g/#{@current_story}/rooms/#{location}"}
              class="map-pin"
              style={MapPins.pin_style(pin)}
              aria-label={location.name}
              data-location-name={location.name}
              title={location.name}
            >
              <span class="map-pin-marker" aria-hidden="true">
                <span class="map-pin-index">{index}</span>
              </span>
              <span
                :if={location.private}
                class="map-pin-lock"
                aria-hidden="true"
              >
                <.icon name="hero-lock-closed" class="size-2.5" />
              </span>
              <span
                class="map-pin-label"
                style={MapPins.label_style(pin)}
                data-placed={pin.label && "true"}
                aria-hidden="true"
              >
                {location.name}
              </span>
            </.link>
          </nav>
        </div>

        <aside class="map-legend self-start rounded-xl border border-mint/20 bg-ink/70 p-4 backdrop-blur">
          <h2 class="flex items-center gap-2 text-sm font-bold uppercase tracking-[0.2em] text-mint">
            <.icon name="hero-map-pin" class="size-4" /> {dgettext("player", "Locations")}
          </h2>
          <ul id="room-list" class="mt-3 space-y-2">
            <li :for={{location, index} <- Enum.with_index(@story.locations, 1)}>
              <.link
                id={"room-link-#{location.id}"}
                navigate={~p"/g/#{@current_story}/rooms/#{location}"}
                class="group flex items-center justify-between gap-3 rounded-md border border-mint/20 bg-ink/80 px-3 py-2 text-sm transition duration-150 hover:-translate-y-px hover:border-phosphor/60 hover:text-phosphor"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <span
                    class="map-legend-index"
                    style={"--pin-color: #{location.color}"}
                    aria-hidden="true"
                  >
                    {index}
                  </span>
                  <span class="truncate">{location.name}</span>
                  <.icon
                    :if={location.private}
                    name="hero-lock-closed"
                    class="size-3 text-error"
                  />
                  <span
                    :if={@weathers[location.zone_id]}
                    id={"room-weather-#{location.id}"}
                    title={@weathers[location.zone_id].condition}
                    class="text-info"
                  >
                    <.icon name={@weathers[location.zone_id].icon} class="size-3.5" />
                  </span>
                </span>

                <span class="text-xs text-fog-500">{Map.get(@counts, location.id, 0)} {dgettext(
                  "player",
                  "msg"
                )}</span>
              </.link>

              <p
                :if={@guild_names[location.guild_id]}
                id={"room-guild-#{location.id}"}
                class="mt-1 flex items-center gap-1 px-3 text-xs text-primary/80"
              >
                <.icon name="hero-flag" class="size-3" /> {@guild_names[location.guild_id]}
              </p>

              <p
                :if={location.private}
                id={"room-bookings-#{location.id}"}
                class="mt-1 px-3 text-xs text-fog-400"
              >
                {booking_line(Map.get(@bookings, location.id, []))}
              </p>
            </li>
          </ul>

          <section :if={@weather? and @zones != []} id="map-weather" class="mt-6">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-mint">
              {dgettext("player", "Weather")}
            </h2>

            <ul class="mt-3 space-y-2">
              <li
                :for={zone <- @zones}
                id={"map-weather-zone-#{zone.id}"}
                class="flex items-center justify-between gap-2 rounded-md border border-mint/20 bg-ink/80 px-3 py-2 text-sm"
              >
                <span class="truncate">{zone.name}</span>
                <.weather_badge
                  :if={@weathers[zone.id]}
                  id={"map-weather-badge-#{zone.id}"}
                  weather={@weathers[zone.id]}
                />
                <span :if={!@weathers[zone.id]} class="text-xs text-fog-500">{dgettext(
                  "player",
                  "Unknown"
                )}</span>
              </li>
            </ul>
          </section>

          <.link
            id="map-guide-link"
            navigate={~p"/g/#{@story}/guide"}
            class="mt-6 flex items-center gap-2 rounded-md border border-mint/20 bg-ink/80 p-3 text-sm font-semibold text-mint transition-colors hover:border-mint/50"
          >
            <.icon name="hero-book-open" class="size-4" /> {dgettext(
              "player",
              "World guide: background, rules, customs"
            )}
          </.link>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
