defmodule TannhauserGateWeb.MasterLive.Items do
  @moduledoc """
  Masters grant and remove items (items module) and read the item log of the
  GDR, optionally filtered by character.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Characters, Items}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :items}}
  on_mount {TannhauserGateWeb.UserAuth, {:require_permission, :can_manage_economy}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "Items")
     |> assign(:characters, Characters.list_story_characters(story.id))
     |> assign(:items, Items.list_items(story))
     |> assign(:filter, "")
     |> assign(:form, new_form())
     |> load_logs()}
  end

  defp new_form(params \\ %{"character_id" => "", "item_id" => "", "quantity" => "1"}),
    do: to_form(params, as: :grant)

  defp load_logs(socket) do
    logs =
      Items.list_logs(socket.assigns.current_story, character_id: socket.assigns.filter)

    stream(socket, :logs, logs, reset: true)
  end

  @impl true
  def handle_event("apply", %{"grant" => params} = all, socket) do
    %{current_story: story, current_user: user} = socket.assigns

    result =
      case Enum.find(socket.assigns.characters, &(to_string(&1.id) == params["character_id"])) do
        nil ->
          {:error, :recipient_not_found}

        character ->
          character = %{character | story: story}

          case all["op"] do
            "remove" ->
              Items.remove(character, params["item_id"], params["quantity"], user, params["note"])

            _ ->
              Items.grant(character, params["item_id"], params["quantity"], user, params["note"])
          end
      end

    case result do
      {:ok, %{item: item, quantity: qty}} ->
        verb = if all["op"] == "remove", do: "Removed", else: "Granted"

        {:noreply,
         socket
         |> put_flash(:info, "#{verb} #{qty}× #{item.name}.")
         |> assign(:form, new_form(Map.put(params, "note", "")))
         |> load_logs()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Items.error_message(reason))
         |> assign(:form, new_form(params))}
    end
  end

  def handle_event("filter", %{"filter" => %{"character_id" => id}}, socket),
    do: {:noreply, socket |> assign(:filter, id) |> load_logs()}

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
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master tools
        </.link>
      </div>

      <.header>
        Items
        <:subtitle>Grant and remove items, and read every item movement of the GDR.</:subtitle>
      </.header>

      <div class="mt-6 grid gap-6 lg:grid-cols-[22rem_1fr]">
        <section class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            Grant or remove
          </h2>
          <p :if={@items == []} class="mt-2 text-xs text-warning">
            The catalog is empty: the GDR admin adds items in the GM dashboard.
          </p>
          <.form for={@form} id="grant-form" phx-submit="apply" class="mt-4">
            <.input
              field={@form[:character_id]}
              type="select"
              label="Character"
              prompt="Choose a character"
              options={Enum.map(@characters, &{&1.name, &1.id})}
            />
            <.input
              field={@form[:item_id]}
              type="select"
              label="Item"
              prompt="Choose an item"
              options={Enum.map(@items, &{&1.name, &1.id})}
            />
            <.input field={@form[:quantity]} type="number" label="Quantity" min="1" />
            <.input field={@form[:note]} type="text" label="Note (optional)" />
            <div class="flex gap-2">
              <.button id="grant-item" name="op" value="grant" phx-disable-with="Saving...">
                <.icon name="hero-plus-micro" class="size-4" /> Grant
              </.button>
              <.button id="remove-item" name="op" value="remove" phx-disable-with="Saving...">
                <.icon name="hero-minus-micro" class="size-4" /> Remove
              </.button>
            </div>
          </.form>
        </section>

        <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Item log</h2>
            <.form for={%{}} as={:filter} id="item-log-filter" phx-change="filter">
              <select name="filter[character_id]" class="select select-sm" aria-label="Character">
                <option value="">All characters</option>
                <option
                  :for={c <- @characters}
                  value={c.id}
                  selected={to_string(c.id) == @filter}
                >
                  {c.name}
                </option>
              </select>
            </.form>
          </div>

          <ul id="item-logs" phx-update="stream" class="mt-3 divide-y divide-secondary/10 text-sm">
            <li id="item-logs-empty" class="hidden py-2 text-base-content/60 only:block">
              Nothing recorded yet.
            </li>
            <li
              :for={{dom_id, log} <- @streams.logs}
              id={dom_id}
              class="flex flex-wrap items-baseline gap-x-2 py-2 transition-colors hover:bg-base-100/30"
            >
              <span class="font-semibold text-primary">
                {(log.character && log.character.name) || "—"}
              </span>
              <span class="text-base-content/70">{Items.action_label(log.action)}</span>
              <span class="font-semibold">{log.quantity}× {log.item_name}</span>
              <span :if={log.target_character} class="text-base-content/70">
                to {log.target_character.name}
              </span>
              <span :if={log.note} class="text-base-content/50">· {log.note}</span>
              <span class="ml-auto text-xs text-base-content/50">
                {(log.user && log.user.username) || "system"} · {Calendar.strftime(
                  log.inserted_at,
                  "%d/%m/%Y %H:%M"
                )}
              </span>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
