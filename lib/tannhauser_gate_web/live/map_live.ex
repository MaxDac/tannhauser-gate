defmodule TannhauserGateWeb.MapLive do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Chat, Stories}
  alias TannhauserGate.Stories.Location

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:stories, Stories.list_stories())
     |> assign(:counts, Chat.count_messages_by_location())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    story =
      case params do
        %{"story_id" => id} -> Stories.get_story!(id)
        _ -> Stories.get_default_story()
      end

    {:noreply,
     socket
     |> assign(:story, story)
     |> assign(:page_title, if(story, do: "#{story.name} · Map", else: "Map"))}
  end

  @impl true
  def handle_event("enter_room", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/rooms/#{id}")}
  end

  def handle_event("select_story", %{"story_id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/stories/#{id}/map")}
  end

  @impl true
  def render(%{story: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.header>City Map</.header>
      <p class="mt-8 text-fog-400">No story has been created yet. Ask an admin to create one.</p>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.header>
        {@story.name}
        <:subtitle>{@story.summary}</:subtitle>
        <:actions>
          <form :if={length(@stories) > 1} id="story-select" phx-change="select_story">
            <select
              id="map-story"
              name="story_id"
              class="select select-sm console-field w-full"
              aria-label="Story"
            >
              {Phoenix.HTML.Form.options_for_select(Enum.map(@stories, &{&1.name, &1.id}), @story.id)}
            </select>
          </form>
        </:actions>
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
            {raw(@story.map_svg || "")}
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
                navigate={~p"/rooms/#{location}"}
                class="flex items-center justify-between gap-3 rounded-md border border-mint/20 bg-ink/80 px-3 py-2 text-sm hover:border-phosphor/60 hover:text-phosphor"
              >
                <span class="flex items-center gap-2">
                  <span class="h-2.5 w-2.5 rounded-full" style={"background: #{location.color}"}></span>
                  {location.name}
                </span>
                <span class="text-xs text-fog-500">{Map.get(@counts, location.id, 0)} msg</span>
              </.link>
            </li>
          </ul>

          <details class="mt-6 rounded-md border border-mint/20 bg-ink/80 p-3 text-sm">
            <summary class="cursor-pointer font-semibold text-mint">World background</summary>
            <p class="mt-2 whitespace-pre-line text-fog-300">{@story.world_background}</p>
          </details>
          <details class="mt-3 rounded-md border border-mint/20 bg-ink/80 p-3 text-sm">
            <summary class="cursor-pointer font-semibold text-mint">Customs</summary>
            <p class="mt-2 whitespace-pre-line text-fog-300">{@story.customs}</p>
          </details>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
