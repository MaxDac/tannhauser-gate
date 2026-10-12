defmodule TannhauserGateWeb.MapLive do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Bookings, Chat, Stories}
  alias TannhauserGate.Stories.Location

  @impl true
  def mount(_params, _session, socket) do
    story = Stories.get_story!(socket.assigns.current_story.id)

    {:ok,
     socket
     |> assign(:story, story)
     |> assign(:counts, Chat.count_messages_by_location())
     |> assign(:bookings, Bookings.upcoming_by_location(story.id))
     |> assign(:page_title, "#{story.name} · Map")}
  end

  @impl true
  def handle_event("enter_room", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/g/#{socket.assigns.current_story}/rooms/#{id}")}
  end

  defp booking_line([]), do: "Private: free to book."

  defp booking_line([booking | rest]) do
    now = DateTime.utc_now()
    who = booking.character.name
    more = if rest == [], do: "", else: " (+#{length(rest)} more)"

    if DateTime.compare(booking.starts_at, now) == :gt,
      do:
        "Next booking: #{who}, #{Calendar.strftime(booking.starts_at, "%d %b %H:%M")} UTC#{more}",
      else: "Booked by #{who} until #{Calendar.strftime(booking.ends_at, "%H:%M")} UTC#{more}"
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
      mail_unread={@mail_unread}
    >
      <.header>
        {@story.name}
        <:subtitle>{@story.summary}</:subtitle>
      </.header>

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_18rem]">
        <div class="self-start overflow-hidden rounded-xl border border-mint/30 bg-night shadow-phosphor">
          <svg
            id="city-map"
            viewBox={"0 0 #{@story.map_width} #{@story.map_height}"}
            class="block h-auto w-full"
            role="img"
            aria-label={"Map of #{@story.name}"}
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
              <text
                x={elem(Location.centroid(location), 0)}
                y={elem(Location.centroid(location), 1)}
                text-anchor="middle"
                dominant-baseline="middle"
                pointer-events="none"
                class="map-label"
              >
                {location.name}
              </text>
            </g>
          </svg>
        </div>

        <aside>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-mint">Rooms</h2>
          <ul id="room-list" class="mt-3 space-y-2">
            <li :for={location <- @story.locations}>
              <.link
                navigate={~p"/g/#{@current_story}/rooms/#{location}"}
                class="flex items-center justify-between gap-3 rounded-md border border-mint/20 bg-ink/80 px-3 py-2 text-sm hover:border-phosphor/60 hover:text-phosphor"
              >
                <span class="flex items-center gap-2">
                  <span class="h-2.5 w-2.5 rounded-full" style={"background: #{location.color}"}></span>
                  {location.name}
                  <.icon
                    :if={location.private}
                    name="hero-lock-closed"
                    class="size-3 text-error"
                  />
                </span>
                <span class="text-xs text-fog-500">{Map.get(@counts, location.id, 0)} msg</span>
              </.link>
              <p
                :if={location.private}
                id={"room-bookings-#{location.id}"}
                class="mt-1 px-3 text-xs text-fog-400"
              >
                {booking_line(Map.get(@bookings, location.id, []))}
              </p>
            </li>
          </ul>

          <.link
            id="map-guide-link"
            navigate={~p"/g/#{@story}/guide"}
            class="mt-6 flex items-center gap-2 rounded-md border border-mint/20 bg-ink/80 p-3 text-sm font-semibold text-mint transition-colors hover:border-mint/50"
          >
            <.icon name="hero-book-open" class="size-4" /> World guide: background, rules, customs
          </.link>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
