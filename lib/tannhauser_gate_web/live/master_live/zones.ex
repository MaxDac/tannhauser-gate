defmodule TannhauserGateWeb.MasterLive.Zones do
  @moduledoc """
  Masters post zone events (title, body, date); players see them in the
  rooms of the zone. Masters also see the hidden zone properties.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Zones
  alias TannhauserGate.Zones.Event

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Zone events")
     |> reload()
     |> reset_form()}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket) do
    story = story(socket)
    zones = Zones.list_zones(story)

    socket
    |> assign(:zones, zones)
    |> assign(:zone_values, Map.new(zones, &{&1.id, Zones.zone_values(&1)}))
    |> assign(:events, Zones.list_story_events(story))
  end

  defp reset_form(socket) do
    form =
      %Event{happened_on: Date.utc_today()}
      |> Zones.change_event()
      |> to_form()

    assign(socket, :form, form)
  end

  @impl true
  def handle_event("post", %{"event" => params}, socket) do
    with {:ok, zone_id} <- parse_id(params["zone_id"]),
         zone when not is_nil(zone) <- Enum.find(socket.assigns.zones, &(&1.id == zone_id)),
         {:ok, _event} <- Zones.create_event(zone, socket.assigns.current_user, params) do
      {:noreply, socket |> put_flash(:info, "Zone event posted.") |> reload() |> reset_form()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a zone.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Zones.get_event!(id) |> Zones.delete_event()
    {:noreply, socket |> put_flash(:info, "Zone event deleted.") |> reload()}
  end

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {id, ""} -> {:ok, id}
      _ -> :error
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
      mail_unread={@mail_unread}
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
        Zone events
        <:subtitle>What happens in the zones of {@current_story.name}.</:subtitle>
      </.header>

      <p
        :if={@zones == []}
        id="master-zones-empty"
        class="mt-6 rounded-md border border-secondary/20 p-4 text-sm text-base-content/60"
      >
        This GDR has no zones yet: the GDR admin defines them in GM config.
      </p>

      <div :if={@zones != []} class="mt-6 grid gap-6 lg:grid-cols-[1fr_20rem]">
        <div class="space-y-6">
          <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">New event</h2>
            <.form for={@form} id="zone-event-form" phx-submit="post" class="mt-3">
              <div class="grid gap-3 sm:grid-cols-2">
                <.input
                  name="event[zone_id]"
                  id="zone-event-zone"
                  type="select"
                  label="Zone"
                  prompt="Choose a zone"
                  options={Enum.map(@zones, &{&1.name, &1.id})}
                  value={nil}
                />
                <.input field={@form[:happened_on]} type="date" label="Date" required />
              </div>
              <.input field={@form[:title]} type="text" label="Title" required />
              <.input field={@form[:body]} type="textarea" label="What happened (Markdown)" rows="5" />
              <.button id="post-zone-event" phx-disable-with="Posting...">Post event</.button>
            </.form>
          </section>

          <section id="zone-events" class="space-y-3">
            <p :if={@events == []} class="text-sm text-base-content/60">No events yet.</p>
            <article
              :for={event <- @events}
              id={"zone-event-#{event.id}"}
              class="rounded-xl border border-secondary/20 bg-base-200/60 p-4"
            >
              <div class="flex items-start justify-between gap-2">
                <div>
                  <h3 class="font-semibold text-primary">{event.title}</h3>
                  <p class="text-xs text-base-content/60">
                    {event.zone.name} · {event.happened_on}
                    <span :if={event.user}>· {event.user.username}</span>
                  </p>
                </div>
                <button
                  id={"delete-zone-event-#{event.id}"}
                  phx-click="delete"
                  phx-value-id={event.id}
                  data-confirm="Delete this event?"
                  class="rounded p-1 text-base-content/60 hover:text-error"
                  title="Delete"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
              <.markdown content={event.body} class="mt-2 text-sm" />
            </article>
          </section>
        </div>

        <aside id="master-zones-list" class="space-y-3">
          <div
            :for={zone <- @zones}
            id={"master-zone-#{zone.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4 text-sm"
          >
            <h3 class="font-semibold text-primary">{zone.name}</h3>
            <ul class="mt-1 space-y-0.5 text-xs">
              <li :for={{property, value} <- Map.get(@zone_values, zone.id, [])}>
                {property.name}: <strong>{value}</strong>
                <span :if={!property.public} class="text-warning">(hidden)</span>
              </li>
            </ul>
            <p class="mt-1 text-xs text-base-content/60">
              {Enum.map_join(zone.locations, ", ", & &1.name)}
            </p>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
