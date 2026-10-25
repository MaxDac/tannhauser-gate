defmodule TannhauserGateWeb.MarketLive do
  @moduledoc """
  The market of a GDR (items module): every shop, the ones placed in a room
  included, with their listings. The user's playable character buys items
  (`TannhauserGate.Items.buy/4`).
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Items}
  alias TannhauserGate.Items.Listing

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :items}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, dgettext("player", "Market · %{name}", name: story.name))
     |> assign(:shops, Items.list_shops(story))
     |> assign(:shop, nil)
     |> load_buyer()}
  end

  defp load_buyer(socket) do
    %{current_user: user, current_story: story} = socket.assigns
    character = Characters.active_character(user, story)

    socket
    |> assign(:character, character)
    |> assign(:buyer, if(character && Characters.can_play?(character), do: character))
  end

  @impl true
  def handle_params(%{"shop_id" => id}, _uri, socket) do
    story = socket.assigns.current_story

    case Items.get_shop(story, id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("player", "That shop does not exist in this GDR."))
         |> push_patch(to: ~p"/g/#{story}/market")}

      shop ->
        {:noreply, socket |> assign(:shop, shop) |> assign(:page_title, shop.name)}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, :shop, nil)}

  @impl true
  def handle_event("buy", %{"listing_id" => listing_id} = params, socket) do
    %{buyer: buyer, current_user: user, current_story: story} = socket.assigns

    result =
      if buyer,
        do: Items.buy(buyer, listing_id, params["quantity"], user),
        else: {:error, :no_buyer}

    case result do
      {:ok, %{item: item, quantity: qty, total: total}} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("player", "Bought %{qty}× %{name} for %{total} %{currency_name}.",
             qty: qty,
             name: item.name,
             total: total,
             currency_name: story.currency_name
           )
         )
         |> refresh()}

      {:error, :no_buyer} ->
        {:noreply,
         put_flash(socket, :error, dgettext("player", "You need an approved character to buy."))}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Items.error_message(reason)) |> refresh()}
    end
  end

  defp refresh(socket) do
    story = socket.assigns.current_story
    shop = socket.assigns.shop && Items.get_shop(story, socket.assigns.shop.id)

    socket
    |> assign(:shops, Items.list_shops(story))
    |> assign(:shop, shop)
    |> load_buyer()
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
        <span :if={!@shop}>{dgettext("player", "Market")}</span> <span :if={@shop}>{@shop.name}</span>
        <:subtitle>
          <%= if @shop do %>
            <span :if={@shop.location}>
              <.icon name="hero-map-pin-micro" class="size-3" />
              <.link
                id="shop-room-link"
                navigate={~p"/g/#{@current_story}/rooms/#{@shop.location}"}
                class="underline decoration-dotted hover:text-primary"
              >
                {@shop.location.name}
              </.link>
            </span>
          <% else %>
            {dgettext("player", "Shops, stalls and fences of")} {@current_story.name}.
          <% end %>
        </:subtitle>

        <:actions>
          <div
            :if={@character}
            id="market-balance"
            class="rounded-lg border border-secondary/20 bg-base-200/80 px-4 py-2 text-right"
          >
            <p class="text-xs uppercase tracking-[0.2em] text-secondary">{@character.name}</p>

            <p class="font-bold text-primary tabular-nums">
              {@character.balance} {@current_story.currency_name}
            </p>
          </div>
        </:actions>
      </.header>

      <p
        :if={!@buyer}
        id="market-no-buyer"
        class="mt-4 rounded-lg border border-warning/30 bg-warning/5 px-4 py-3 text-sm"
      >
        <.icon name="hero-information-circle" class="size-4 text-warning" /> {dgettext(
          "player",
          "You can browse, but only an approved character that can play may buy."
        )}
      </p>

      <%= if @shop do %>
        <div class="mt-4">
          <.link
            id="market-back"
            patch={~p"/g/#{@current_story}/market"}
            class="text-sm font-semibold text-secondary transition-colors hover:text-primary"
          >
            <.icon name="hero-arrow-left-micro" class="size-4" /> {dgettext("player", "All shops")}
          </.link>
        </div>

        <.markdown
          :if={@shop.description}
          content={@shop.description}
          class="mt-4 max-w-3xl text-sm text-base-content/80"
        />
        <p :if={@shop.listings == []} id="shop-empty" class="mt-6 text-sm text-base-content/60">
          {dgettext("player", "The shelves are empty.")}
        </p>

        <ul id="shop-listings" class="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          <li
            :for={listing <- @shop.listings}
            id={"shop-listing-#{listing.id}"}
            class="group flex flex-col rounded-xl border border-secondary/20 bg-base-200/70 p-4 transition hover:-translate-y-0.5 hover:border-primary/50 hover:shadow-phosphor"
          >
            <div class="flex gap-3">
              <img
                :if={listing.item.image_path}
                src={listing.item.image_path}
                alt=""
                class="size-16 shrink-0 rounded object-cover"
              />
              <div class="min-w-0 flex-1">
                <p class="font-semibold text-primary">{listing.item.name}</p>

                <p class="text-xs text-base-content/60">
                  {listing.item.category} <span :if={listing.item.slot}>· {listing.item.slot}</span>
                </p>

                <p
                  :if={TannhauserGate.Origins.bonus_label(listing.item.modifiers)}
                  class="text-xs tabular-nums text-secondary"
                >
                  {TannhauserGate.Origins.bonus_label(listing.item.modifiers)}
                </p>
              </div>

              <div class="shrink-0 text-right">
                <p class="font-bold tabular-nums text-primary">
                  {Listing.unit_price(listing)}
                </p>

                <p id={"shop-stock-#{listing.id}"} class="text-xs text-base-content/60">
                  {if listing.stock,
                    do: dgettext("player", "%{stock} left", stock: listing.stock),
                    else: dgettext("player", "In stock")}
                </p>
              </div>
            </div>

            <.markdown
              :if={listing.item.description}
              content={listing.item.description}
              class="mt-2 flex-1 text-sm text-base-content/80"
            />
            <.form
              :if={@buyer && listing.stock != 0}
              for={%{}}
              id={"buy-form-#{listing.id}"}
              phx-submit="buy"
              class="mt-3 flex items-center justify-end gap-2"
            >
              <input type="hidden" name="listing_id" value={listing.id} />
              <input
                type="number"
                name="quantity"
                value="1"
                min="1"
                max={listing.stock}
                aria-label={dgettext("player", "Quantity")}
                class="input input-sm w-20"
              />
              <button class="btn btn-sm btn-primary transition hover:scale-105">
                <.icon name="hero-shopping-cart-micro" class="size-4" /> {dgettext("player", "Buy")}
              </button>
            </.form>

            <p :if={listing.stock == 0} class="mt-3 text-right text-xs font-bold text-error">
              {dgettext("player", "Sold out")}
            </p>
          </li>
        </ul>
      <% else %>
        <p :if={@shops == []} id="market-empty" class="mt-6 text-sm text-base-content/60">
          {dgettext("player", "No shops are open yet.")}
        </p>

        <ul id="market-shops" class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <li :for={shop <- @shops} id={"market-shop-#{shop.id}"}>
            <.link
              patch={~p"/g/#{@current_story}/market/#{shop}"}
              class="flex h-full flex-col gap-2 rounded-xl border border-secondary/20 bg-base-200/80 p-5 transition hover:-translate-y-0.5 hover:border-primary hover:shadow-phosphor"
            >
              <span class="flex items-center gap-2 font-bold uppercase tracking-wider text-primary">
                <.icon name="hero-building-storefront" class="size-5" /> {shop.name}
              </span>

              <span class="text-xs text-base-content/60">
                <.icon name="hero-map-pin-micro" class="size-3" /> {if shop.location,
                  do: shop.location.name,
                  else: dgettext("player", "Market")} · {length(shop.listings)} {dgettext(
                  "player",
                  "items"
                )}
              </span>
            </.link>
          </li>
        </ul>
      <% end %>
    </Layouts.app>
    """
  end
end
