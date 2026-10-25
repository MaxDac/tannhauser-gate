defmodule TannhauserGateWeb.GmLive.Zones do
  @moduledoc """
  GM config: the GDR admin defines the zone properties (numeric, e.g. danger)
  and the zones, setting each property's value on every zone. Locations are
  assigned to a zone from the map tab.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.Zones
  alias TannhauserGate.Zones.{Property, Zone}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "GM dashboard")
     |> reload()
     |> edit_property(%Property{})
     |> edit_zone(%Zone{story_id: socket.assigns.current_story.id})}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket) do
    assign(socket,
      properties: Zones.list_properties(story(socket)),
      zones: Zones.list_zones(story(socket))
    )
  end

  defp edit_property(socket, property) do
    assign(socket, property: property, property_form: to_form(Zones.change_property(property)))
  end

  defp edit_zone(socket, zone) do
    assign(socket,
      zone: zone,
      zone_form: to_form(Zones.change_zone(zone)),
      zone_values: Map.new(zone.values || %{}, fn {k, v} -> {k, to_string(v)} end)
    )
  end

  @impl true
  def handle_event("save_property", %{"property" => params}, socket) do
    result =
      case socket.assigns.property do
        %Property{id: nil} -> Zones.create_property(story(socket), params)
        property -> Zones.update_property(property, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Property saved.") |> reload() |> edit_property(%Property{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :property_form, to_form(changeset))}
    end
  end

  def handle_event("edit_property", %{"id" => id}, socket),
    do: {:noreply, edit_property(socket, Zones.get_property!(story(socket), id))}

  def handle_event("cancel_property", _, socket),
    do: {:noreply, edit_property(socket, %Property{})}

  def handle_event("delete_property", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Zones.get_property!(id) |> Zones.delete_property()

    {:noreply,
     socket |> put_flash(:info, "Property deleted.") |> reload() |> edit_property(%Property{})}
  end

  def handle_event("save_zone", %{"zone" => params}, socket) do
    params = Map.put_new(params, "values", %{})

    result =
      case socket.assigns.zone do
        %Zone{id: nil} -> Zones.create_zone(story(socket), params)
        zone -> Zones.update_zone(zone, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Zone saved.")
         |> reload()
         |> edit_zone(%Zone{story_id: story(socket).id})}

      {:error, changeset} ->
        {:noreply,
         assign(socket, zone_form: to_form(changeset), zone_values: params["values"] || %{})}
    end
  end

  def handle_event("edit_zone", %{"id" => id}, socket),
    do: {:noreply, edit_zone(socket, Zones.get_zone!(story(socket), id))}

  def handle_event("cancel_zone", _, socket),
    do: {:noreply, edit_zone(socket, %Zone{story_id: story(socket).id})}

  def handle_event("delete_zone", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Zones.get_zone!(id) |> Zones.delete_zone()

    {:noreply,
     socket
     |> put_flash(:info, "Zone deleted.")
     |> reload()
     |> edit_zone(%Zone{story_id: story(socket).id})}
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
      announcements_unread={@announcements_unread}
    >
      <.gm_header story={@current_story} />
      <.gm_tabs story={@current_story} tab="zones" />

      <div class="mt-6 grid gap-6 xl:grid-cols-2">
        <section id="zone-properties" class="space-y-4">
          <div class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              Zone properties
            </h2>
            <p class="mt-1 text-sm text-base-content/70">
              Numeric values every zone carries (e.g. danger, resonance). Periodic actions can
              use them as difficulty. Hidden properties are only shown to masters.
            </p>
            <.form for={@property_form} id="property-form" phx-submit="save_property" class="mt-3">
              <div class="grid gap-3 sm:grid-cols-2">
                <.input field={@property_form[:name]} type="text" label="Name" required />
                <.input field={@property_form[:slug]} type="text" label="Key (optional)" />
                <.input field={@property_form[:default_value]} type="number" label="Default value" />
                <.input field={@property_form[:position]} type="number" label="Position" min="0" />
              </div>
              <.input field={@property_form[:public]} type="checkbox" label="Visible to players" />
              <div class="flex gap-2">
                <.button id="save-property">
                  {if @property.id, do: "Update property", else: "Add property"}
                </.button>
                <.button
                  :if={@property.id}
                  type="button"
                  id="cancel-property"
                  phx-click="cancel_property"
                >
                  Cancel
                </.button>
              </div>
            </.form>
          </div>

          <ul id="zone-properties-list" class="space-y-2">
            <li
              :for={property <- @properties}
              id={"zone-property-#{property.id}"}
              class="flex items-center justify-between rounded-lg border border-secondary/20 bg-base-200/60 px-4 py-2"
            >
              <div>
                <span class="font-semibold text-primary">{property.name}</span>
                <code class="ml-2 text-xs text-base-content/60">{property.slug}</code>
                <span class="ml-2 text-xs text-base-content/60">default {property.default_value}</span>
                <span :if={!property.public} class="ml-2 text-xs text-warning">hidden</span>
              </div>
              <div class="flex gap-1">
                <button
                  id={"edit-property-#{property.id}"}
                  phx-click="edit_property"
                  phx-value-id={property.id}
                  class="rounded p-1 text-base-content/60 hover:text-secondary"
                  title="Edit"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  id={"delete-property-#{property.id}"}
                  phx-click="delete_property"
                  phx-value-id={property.id}
                  data-confirm="Delete this property?"
                  class="rounded p-1 text-base-content/60 hover:text-error"
                  title="Delete"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </li>
          </ul>
        </section>

        <section id="zones" class="space-y-4">
          <div class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @zone.id, do: "Edit zone", else: "New zone"}
            </h2>
            <p class="mt-1 text-sm text-base-content/70">
              Zones group locations; assign each location to a zone from the <.link
                navigate={~p"/g/#{@current_story}/gm/map"}
                class="link link-primary"
              >map tab</.link>.
            </p>
            <.form for={@zone_form} id="zone-form" phx-submit="save_zone" class="mt-3">
              <.input field={@zone_form[:name]} type="text" label="Name" required />
              <.input field={@zone_form[:description]} type="textarea" label="Description" rows="3" />
              <div :if={@properties != []} class="grid gap-3 sm:grid-cols-3">
                <.input
                  :for={property <- @properties}
                  type="number"
                  id={"zone-value-#{property.slug}"}
                  name={"zone[values][#{property.slug}]"}
                  label={property.name}
                  value={Map.get(@zone_values, property.slug, property.default_value)}
                />
              </div>
              <p
                :for={{msg, _} <- Keyword.get_values(@zone_form.errors, :values)}
                class="text-sm text-error"
              >
                {msg}
              </p>
              <div class="flex gap-2">
                <.button id="save-zone">{if @zone.id, do: "Update zone", else: "Add zone"}</.button>
                <.button :if={@zone.id} type="button" id="cancel-zone" phx-click="cancel_zone">
                  Cancel
                </.button>
              </div>
            </.form>
          </div>

          <p :if={@zones == []} id="zones-empty" class="text-sm text-base-content/60">
            No zones yet.
          </p>

          <div
            :for={zone <- @zones}
            id={"zone-#{zone.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4"
          >
            <div class="flex items-center justify-between">
              <h3 class="font-semibold text-primary">{zone.name}</h3>
              <div class="flex gap-1">
                <button
                  id={"edit-zone-#{zone.id}"}
                  phx-click="edit_zone"
                  phx-value-id={zone.id}
                  class="rounded p-1 text-base-content/60 hover:text-secondary"
                  title="Edit"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  id={"delete-zone-#{zone.id}"}
                  phx-click="delete_zone"
                  phx-value-id={zone.id}
                  data-confirm="Delete this zone? Its locations will have no zone."
                  class="rounded p-1 text-base-content/60 hover:text-error"
                  title="Delete"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
            <p :if={zone.description} class="mt-1 text-sm text-base-content/70">{zone.description}</p>
            <div class="mt-2 flex flex-wrap gap-2">
              <span
                :for={property <- @properties}
                class="rounded-full bg-base-300/70 px-2 py-0.5 text-xs"
              >
                {property.name}:
                <strong>{Map.get(zone.values, property.slug, property.default_value)}</strong>
              </span>
            </div>
            <p class="mt-2 text-xs text-base-content/60">
              Locations: <span :if={zone.locations == []}>none</span>
              {Enum.map_join(zone.locations, ", ", & &1.name)}
            </p>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
