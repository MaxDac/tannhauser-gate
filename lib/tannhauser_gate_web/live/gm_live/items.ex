defmodule TannhauserGateWeb.GmLive.Items do
  @moduledoc """
  GM config for the items module: the item catalog of the GDR (name,
  Markdown description, image, category, price, stackable flag, equipment
  slot with sheet modifiers and an optional consumable tracker effect).
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.{Items, Origins, Sheet, Storage, Trackers}
  alias TannhauserGate.Items.Item

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :items}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "GM dashboard")
     |> assign(:sheet_items, Sheet.list_items(story))
     |> assign(:trackers, Trackers.list_trackers(story))
     |> allow_upload(:image,
       accept: Storage.allowed_extensions(),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> reload()
     |> edit_item(%Item{})}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket) do
    story = story(socket)

    socket
    |> assign(:items, Items.list_items(story))
    |> assign(:categories, Items.categories(story))
    |> assign(:slots, Items.slots(story))
  end

  defp edit_item(socket, item) do
    assign(socket, item: item, form: to_form(Items.change_item(story(socket), item)))
  end

  @impl true
  def handle_event("validate", %{"item" => params}, socket) do
    changeset =
      story(socket)
      |> Items.change_item(socket.assigns.item, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"item" => params}, socket) do
    image_path =
      socket
      |> consume_uploaded_entries(:image, fn %{path: path}, entry ->
        {:ok, Storage.store_upload!(path, entry.client_name)}
      end)
      |> List.first()

    result =
      case socket.assigns.item do
        %Item{id: nil} -> Items.create_item(story(socket), params, image_path)
        item -> Items.update_item(story(socket), item, params, image_path)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item saved.")
         |> reload()
         |> edit_item(%Item{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket),
    do: {:noreply, edit_item(socket, Items.get_item!(story(socket), id))}

  def handle_event("cancel", _, socket), do: {:noreply, edit_item(socket, %Item{})}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :image, ref)}

  def handle_event("remove_image", _, socket) do
    case socket.assigns.item do
      %Item{id: id} = item when is_integer(id) ->
        {:ok, item} = Items.remove_item_image(item)
        {:noreply, socket |> reload() |> edit_item(item)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Items.get_item!(id) |> Items.delete_item()

    {:noreply,
     socket
     |> put_flash(:info, "Item deleted.")
     |> reload()
     |> edit_item(%Item{})}
  end

  defp modifier_value(form, slug) do
    case form[:modifiers].value do
      %{} = modifiers -> Map.get(modifiers, slug, "")
      _ -> ""
    end
  end

  # The damage types of the tracker currently picked in the form.
  defp damage_types(form, trackers) do
    id = form[:tracker_id].value |> to_string()

    case Enum.find(trackers, &(to_string(&1.id) == id)) do
      nil -> []
      tracker -> tracker.damage_types
    end
  end

  defp upload_error(:too_large), do: "The image is too large (max 5 MB)"
  defp upload_error(:not_accepted), do: "Unsupported file type"
  defp upload_error(:too_many_files), do: "Only one image is allowed"
  defp upload_error(other), do: "Upload error: #{inspect(other)}"

  @impl true
  def render(assigns) do
    image_errors =
      upload_errors(assigns.uploads.image) ++
        Enum.flat_map(assigns.uploads.image.entries, &upload_errors(assigns.uploads.image, &1))

    assigns =
      assigns
      |> assign(:image_errors, Enum.map(image_errors, &upload_error/1))
      |> assign(:damage_types, damage_types(assigns.form, assigns.trackers))

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
      <.gm_header story={@current_story} />
      <.gm_tabs story={@current_story} tab="items" />

      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_26rem]">
        <section id="item-catalog" class="space-y-3">
          <p :if={@items == []} id="items-empty" class="text-sm text-base-content/60">
            No items yet: add weapons, clothes, medkits and anything your players can carry.
          </p>

          <ul class="grid gap-3 sm:grid-cols-2">
            <li
              :for={item <- @items}
              id={"catalog-item-#{item.id}"}
              class="flex gap-3 rounded-xl border border-secondary/20 bg-base-200/60 p-4 transition hover:-translate-y-0.5 hover:border-primary/40"
            >
              <img
                :if={item.image_path}
                src={item.image_path}
                alt=""
                class="size-14 shrink-0 rounded object-cover"
              />
              <div class="min-w-0 flex-1">
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <p class="truncate font-semibold text-primary">{item.name}</p>
                    <p class="text-xs text-base-content/60">
                      {item.category || "Uncategorised"} · {item.price} {@current_story.currency_name}
                      <span :if={!item.stackable}>· unique</span>
                    </p>
                  </div>
                  <span class="flex shrink-0 gap-1">
                    <button
                      id={"edit-item-#{item.id}"}
                      phx-click="edit"
                      phx-value-id={item.id}
                      class="rounded p-0.5 text-base-content/60 transition-colors hover:text-secondary"
                      title="Edit"
                    >
                      <.icon name="hero-pencil" class="size-4" />
                    </button>
                    <button
                      id={"delete-item-#{item.id}"}
                      phx-click="delete"
                      phx-value-id={item.id}
                      data-confirm="Delete this item? It disappears from every inventory and shop."
                      class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                      title="Delete"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </span>
                </div>
                <div class="mt-2 flex flex-wrap gap-1 text-xs">
                  <span :if={item.slot} class="badge badge-soft badge-sm badge-info">
                    <.icon name="hero-shield-check-micro" class="size-3" /> {item.slot}
                  </span>
                  <span
                    :if={Origins.bonus_label(item.modifiers)}
                    id={"catalog-item-modifiers-#{item.id}"}
                    class="badge badge-soft badge-sm badge-secondary tabular-nums"
                  >
                    {Origins.bonus_label(item.modifiers)}
                  </span>
                  <span
                    :if={Item.usable?(item) and item.tracker}
                    class="badge badge-soft badge-sm badge-success"
                  >
                    <.icon name="hero-beaker-micro" class="size-3" />
                    {item.tracker.name}{if item.effect_damage_type,
                      do: " (#{item.effect_damage_type})"} {Origins.signed(item.effect_change)}
                  </span>
                </div>
              </div>
            </li>
          </ul>
        </section>

        <section class="h-fit rounded-xl border border-secondary/20 bg-base-200/80 p-5">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {if @item.id, do: "Edit item", else: "New item"}
          </h2>
          <.form
            for={@form}
            id="item-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-4"
          >
            <.input field={@form[:name]} type="text" label="Name" required />
            <div class="grid grid-cols-2 gap-3">
              <.input
                field={@form[:category]}
                type="text"
                label="Category"
                list="item-categories"
                placeholder="e.g. Weapons"
              />
              <.input field={@form[:price]} type="number" label="Base price" min="0" />
            </div>
            <datalist id="item-categories">
              <option :for={category <- @categories} value={category} />
            </datalist>
            <.input
              field={@form[:description]}
              type="textarea"
              label="Description (Markdown)"
              rows="4"
            />

            <div phx-drop-target={@uploads.image.ref} class="mb-2 space-y-2">
              <label for={@uploads.image.ref} class="console-label">Image (optional)</label>
              <div class="flex flex-wrap items-center gap-3">
                <img
                  :if={@item.image_path && @uploads.image.entries == []}
                  id="item-image"
                  src={@item.image_path}
                  alt=""
                  class="size-14 rounded object-cover"
                />
                <button
                  :if={@item.image_path && @uploads.image.entries == []}
                  type="button"
                  id="remove-item-image"
                  phx-click="remove_image"
                  class="text-xs text-error hover:underline"
                >
                  Remove
                </button>
                <div :for={entry <- @uploads.image.entries} class="flex items-center gap-2">
                  <.live_img_preview entry={entry} class="size-14 rounded object-cover" />
                  <button
                    type="button"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    class="text-xs text-error hover:underline"
                  >
                    Remove
                  </button>
                </div>
                <.live_file_input
                  upload={@uploads.image}
                  class="file-input file-input-secondary console-field w-full max-w-xs"
                />
              </div>
              <.error :for={error <- @image_errors}>{error}</.error>
            </div>

            <.input
              field={@form[:stackable]}
              type="checkbox"
              label="Stackable (a character can hold more than one)"
            />

            <fieldset id="item-equipment" class="mt-2 rounded-lg border border-secondary/20 p-3">
              <legend class="px-1 text-xs font-bold uppercase tracking-wider text-secondary">
                Equipment
              </legend>
              <.input
                field={@form[:slot]}
                type="text"
                label="Slot (blank = not equippable)"
                list="item-slots"
                placeholder="e.g. weapon, body"
              />
              <datalist id="item-slots">
                <option :for={slot <- @slots} value={slot} />
              </datalist>
              <p class="mb-2 text-xs text-base-content/60">
                One item per slot. While equipped, the modifiers are added to the character's
                values in dice pools, periodic actions, formulas and tracker maximums.
              </p>
              <p :if={@sheet_items == []} class="text-xs text-warning">
                Define sheet items in the Sheet tab to give modifiers.
              </p>
              <div class="grid grid-cols-2 gap-x-3">
                <.input
                  :for={sheet_item <- @sheet_items}
                  type="number"
                  id={"item-modifier-#{sheet_item.slug}"}
                  name={"item[modifiers][#{sheet_item.slug}]"}
                  value={modifier_value(@form, sheet_item.slug)}
                  label={sheet_item.name}
                />
              </div>
              <.error :for={error <- @form[:modifiers].errors}>{translate_error(error)}</.error>
            </fieldset>

            <fieldset id="item-effect" class="mt-3 rounded-lg border border-secondary/20 p-3">
              <legend class="px-1 text-xs font-bold uppercase tracking-wider text-secondary">
                Consumable effect
              </legend>
              <.input
                field={@form[:tracker_id]}
                type="select"
                label="Tracker"
                prompt="No effect"
                options={Enum.map(@trackers, &{&1.name, &1.id})}
              />
              <div :if={@form[:tracker_id].value not in [nil, ""]}>
                <div class="grid grid-cols-2 gap-3">
                  <.input field={@form[:effect_change]} type="number" label="Change" />
                  <.input
                    :if={@damage_types != []}
                    field={@form[:effect_damage_type]}
                    type="select"
                    label="Damage type"
                    prompt="Choose"
                    options={@damage_types}
                  />
                </div>
                <p class="mb-2 text-xs text-base-content/60">
                  Added to the tracker value, or to the damage of the chosen type (negative
                  heals).
                </p>
                <.input
                  field={@form[:consumed_on_use]}
                  type="checkbox"
                  label="Using it consumes one unit"
                />
              </div>
            </fieldset>

            <div class="mt-4 flex gap-2">
              <.button id="save-item" phx-disable-with="Saving...">
                {if @item.id, do: "Update item", else: "Add item"}
              </.button>
              <.button :if={@item.id} type="button" id="cancel-item" phx-click="cancel">
                Cancel
              </.button>
            </div>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
