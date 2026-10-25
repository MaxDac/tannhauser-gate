defmodule TannhauserGateWeb.GmLive.Shops do
  @moduledoc """
  GM config for the items module: the shops of the GDR, optionally placed in
  a room, and their listings (item, price override, stock or unlimited).
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.{Items, Stories}
  alias TannhauserGate.Items.{Listing, Shop}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :items}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "GM dashboard")
     |> assign(:locations, Stories.list_locations(story))
     |> assign(:items, Items.list_items(story))
     |> reload()
     |> edit_shop(%Shop{})
     |> edit_listing(nil)}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket), do: assign(socket, :shops, Items.list_shops(story(socket)))

  defp edit_shop(socket, shop),
    do: assign(socket, shop: shop, shop_form: to_form(Items.change_shop(shop)))

  defp edit_listing(socket, nil), do: assign(socket, listing: nil, listing_form: nil)

  defp edit_listing(socket, listing),
    do: assign(socket, listing: listing, listing_form: to_form(Items.change_listing(listing)))

  @impl true
  def handle_event("validate_shop", %{"shop" => params}, socket) do
    changeset = socket.assigns.shop |> Items.change_shop(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :shop_form, to_form(changeset))}
  end

  def handle_event("save_shop", %{"shop" => params}, socket) do
    result =
      case socket.assigns.shop do
        %Shop{id: nil} -> Items.create_shop(story(socket), params)
        shop -> Items.update_shop(story(socket), shop, params)
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Shop saved.") |> reload() |> edit_shop(%Shop{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :shop_form, to_form(changeset))}
    end
  end

  def handle_event("edit_shop", %{"id" => id}, socket),
    do: {:noreply, edit_shop(socket, Items.get_shop!(story(socket), id))}

  def handle_event("cancel_shop", _, socket), do: {:noreply, edit_shop(socket, %Shop{})}

  def handle_event("delete_shop", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Items.get_shop!(id) |> Items.delete_shop()

    {:noreply,
     socket
     |> put_flash(:info, "Shop deleted.")
     |> reload()
     |> edit_shop(%Shop{})
     |> edit_listing(nil)}
  end

  def handle_event("new_listing", %{"shop" => id}, socket) do
    shop = Items.get_shop!(story(socket), id)
    {:noreply, edit_listing(socket, %Listing{shop_id: shop.id, shop: shop})}
  end

  def handle_event("edit_listing", %{"id" => id}, socket) do
    case Items.get_listing(story(socket), id) do
      nil -> {:noreply, socket}
      listing -> {:noreply, edit_listing(socket, listing)}
    end
  end

  def handle_event("cancel_listing", _, socket), do: {:noreply, edit_listing(socket, nil)}

  def handle_event("validate_listing", %{"listing" => params}, socket) do
    changeset =
      socket.assigns.listing |> Items.change_listing(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :listing_form, to_form(changeset))}
  end

  def handle_event("save_listing", %{"listing" => params}, socket) do
    story = story(socket)

    result =
      case socket.assigns.listing do
        %Listing{id: nil, shop: shop} -> Items.create_listing(story, shop, params)
        %Listing{} = listing -> Items.update_listing(story, listing, params)
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Listing saved.") |> reload() |> edit_listing(nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :listing_form, to_form(changeset))}
    end
  end

  def handle_event("delete_listing", %{"id" => id}, socket) do
    case Items.get_listing(story(socket), id) do
      nil ->
        {:noreply, socket}

      listing ->
        {:ok, _} = Items.delete_listing(listing)

        {:noreply,
         socket |> put_flash(:info, "Listing removed.") |> reload() |> edit_listing(nil)}
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
      announcements_unread={@announcements_unread}
    >
      <.gm_header story={@current_story} />
      <.gm_tabs story={@current_story} tab="shops" />

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_26rem]">
        <section id="shops" class="space-y-4">
          <p :if={@shops == []} id="shops-empty" class="text-sm text-base-content/60">
            No shops yet. Shops appear on the Market page; place one in a room to open it from
            there too.
          </p>

          <article
            :for={shop <- @shops}
            id={"shop-#{shop.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4 transition hover:border-secondary/40"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="font-semibold text-primary">{shop.name}</h3>
                <p class="text-xs text-base-content/60">
                  <.icon name="hero-map-pin-micro" class="size-3" />
                  {if shop.location, do: shop.location.name, else: "Market only"}
                </p>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  id={"new-listing-#{shop.id}"}
                  phx-click="new_listing"
                  phx-value-shop={shop.id}
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-primary"
                  title="Sell an item"
                >
                  <.icon name="hero-plus-circle" class="size-4" />
                </button>
                <button
                  id={"edit-shop-#{shop.id}"}
                  phx-click="edit_shop"
                  phx-value-id={shop.id}
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-secondary"
                  title="Edit"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  id={"delete-shop-#{shop.id}"}
                  phx-click="delete_shop"
                  phx-value-id={shop.id}
                  data-confirm="Delete this shop and its listings?"
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-error"
                  title="Delete"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>

            <p :if={shop.listings == []} class="mt-3 text-xs italic text-base-content/50">
              Nothing for sale yet.
            </p>
            <table :if={shop.listings != []} class="mt-3 w-full text-sm">
              <thead class="text-left text-xs uppercase tracking-wider text-base-content/50">
                <tr>
                  <th class="py-1 font-semibold">Item</th>
                  <th class="py-1 text-right font-semibold">Price</th>
                  <th class="py-1 text-right font-semibold">Stock</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={listing <- shop.listings}
                  id={"listing-#{listing.id}"}
                  class="border-t border-secondary/10 transition-colors hover:bg-base-100/40"
                >
                  <td class="py-1.5">{listing.item.name}</td>
                  <td class="py-1.5 text-right tabular-nums">
                    {Listing.unit_price(listing)}
                    <span :if={is_nil(listing.price)} class="text-xs opacity-50">(base)</span>
                  </td>
                  <td id={"listing-stock-#{listing.id}"} class="py-1.5 text-right tabular-nums">
                    {listing.stock || "∞"}
                  </td>
                  <td class="py-1.5 text-right">
                    <button
                      id={"edit-listing-#{listing.id}"}
                      phx-click="edit_listing"
                      phx-value-id={listing.id}
                      class="rounded p-0.5 text-base-content/60 transition-colors hover:text-secondary"
                      title="Edit"
                    >
                      <.icon name="hero-pencil" class="size-3.5" />
                    </button>
                    <button
                      id={"delete-listing-#{listing.id}"}
                      phx-click="delete_listing"
                      phx-value-id={listing.id}
                      class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                      title="Remove"
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </article>
        </section>

        <div class="space-y-6">
          <section
            :if={@listing_form}
            class="rounded-xl border border-primary/30 bg-base-200/80 p-5"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @listing.id, do: "Edit listing", else: "Sell an item"} · {@listing.shop.name}
            </h2>
            <p :if={@items == []} class="mt-2 text-xs text-warning">
              Create items in the Items tab first.
            </p>
            <.form
              for={@listing_form}
              id="listing-form"
              phx-change="validate_listing"
              phx-submit="save_listing"
              class="mt-4"
            >
              <.input
                field={@listing_form[:item_id]}
                type="select"
                label="Item"
                prompt="Choose an item"
                options={Enum.map(@items, &{"#{&1.name} (#{&1.price})", &1.id})}
              />
              <div class="grid grid-cols-2 gap-3">
                <.input
                  field={@listing_form[:price]}
                  type="number"
                  label="Price (blank = base)"
                  min="0"
                />
                <.input
                  field={@listing_form[:stock]}
                  type="number"
                  label="Stock (blank = ∞)"
                  min="0"
                />
              </div>
              <div class="flex gap-2">
                <.button id="save-listing" phx-disable-with="Saving...">
                  {if @listing.id, do: "Update listing", else: "Add listing"}
                </.button>
                <.button type="button" id="cancel-listing" phx-click="cancel_listing">
                  Cancel
                </.button>
              </div>
            </.form>
          </section>

          <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @shop.id, do: "Edit shop", else: "New shop"}
            </h2>
            <.form
              for={@shop_form}
              id="shop-form"
              phx-change="validate_shop"
              phx-submit="save_shop"
              class="mt-4"
            >
              <.input field={@shop_form[:name]} type="text" label="Name" required />
              <.input
                field={@shop_form[:location_id]}
                type="select"
                label="Room (optional)"
                prompt="Market only"
                options={Enum.map(@locations, &{&1.name, &1.id})}
              />
              <.input
                field={@shop_form[:description]}
                type="textarea"
                label="Description (Markdown)"
                rows="3"
              />
              <div class="flex gap-2">
                <.button id="save-shop" phx-disable-with="Saving...">
                  {if @shop.id, do: "Update shop", else: "Add shop"}
                </.button>
                <.button :if={@shop.id} type="button" id="cancel-shop" phx-click="cancel_shop">
                  Cancel
                </.button>
              </div>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
