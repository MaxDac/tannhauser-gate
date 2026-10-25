defmodule TannhauserGateWeb.GmLive.Origins do
  @moduledoc """
  GM config for the origins module (races & classes): the GDR admin defines
  origin groups (e.g. "Race", "Class") and their options, with a Markdown
  description, an optional image, sheet bonuses and the master approval flag.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.{Origins, Sheet, Storage}
  alias TannhauserGate.Origins.{Group, Option}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :origins}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, dgettext("management", "GM dashboard"))
     |> assign(:items, Sheet.list_items(socket.assigns.current_story))
     |> allow_upload(:image,
       accept: Storage.allowed_extensions(),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> reload()
     |> edit_group(%Group{})
     |> edit_option(new_option(nil))}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket), do: assign(socket, :groups, Origins.list_groups(story(socket)))

  defp new_option(group_id), do: %Option{group_id: group_id}

  defp edit_group(socket, group) do
    assign(socket, group: group, group_form: to_form(Origins.change_group(group)))
  end

  defp edit_option(socket, option) do
    changeset = Origins.change_option(story(socket), option)
    assign(socket, option: option, option_form: to_form(changeset))
  end

  @impl true
  def handle_event("validate_group", %{"group" => params}, socket) do
    changeset =
      socket.assigns.group |> Origins.change_group(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :group_form, to_form(changeset))}
  end

  def handle_event("save_group", %{"group" => params}, socket) do
    result =
      case socket.assigns.group do
        %Group{id: nil} -> Origins.create_group(story(socket), params)
        group -> Origins.update_group(group, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("management", "Origin group saved."))
         |> reload()
         |> edit_group(%Group{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :group_form, to_form(changeset))}
    end
  end

  def handle_event("edit_group", %{"id" => id}, socket),
    do: {:noreply, edit_group(socket, Origins.get_group!(story(socket), id))}

  def handle_event("cancel_group", _, socket), do: {:noreply, edit_group(socket, %Group{})}

  def handle_event("delete_group", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Origins.get_group!(id) |> Origins.delete_group()

    {:noreply,
     socket
     |> put_flash(:info, dgettext("management", "Origin group deleted."))
     |> reload()
     |> edit_group(%Group{})
     |> edit_option(new_option(nil))}
  end

  def handle_event("new_option", %{"group" => id}, socket) do
    group = Origins.get_group!(story(socket), id)
    {:noreply, edit_option(socket, new_option(group.id))}
  end

  def handle_event("validate_option", %{"option" => params}, socket) do
    changeset =
      story(socket)
      |> Origins.change_option(socket.assigns.option, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :option_form, to_form(changeset))}
  end

  def handle_event("save_option", %{"option" => params}, socket) do
    image_path =
      socket
      |> consume_uploaded_entries(:image, fn %{path: path}, entry ->
        {:ok, Storage.store_upload!(path, entry.client_name)}
      end)
      |> List.first()

    result =
      case socket.assigns.option do
        %Option{id: nil} -> Origins.create_option(story(socket), params, image_path)
        option -> Origins.update_option(story(socket), option, params, image_path)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("management", "Origin option saved."))
         |> reload()
         |> edit_option(new_option(nil))}

      {:error, changeset} ->
        {:noreply, assign(socket, :option_form, to_form(changeset))}
    end
  end

  def handle_event("edit_option", %{"id" => id}, socket),
    do: {:noreply, edit_option(socket, Origins.get_option!(story(socket), id))}

  def handle_event("cancel_option", _, socket),
    do: {:noreply, edit_option(socket, new_option(nil))}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :image, ref)}

  def handle_event("remove_image", _, socket) do
    case socket.assigns.option do
      %Option{id: id} = option when is_integer(id) ->
        {:ok, option} = Origins.remove_option_image(option)
        {:noreply, socket |> reload() |> edit_option(option)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_option", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Origins.get_option!(id) |> Origins.delete_option()

    {:noreply,
     socket
     |> put_flash(:info, dgettext("management", "Origin option deleted."))
     |> reload()
     |> edit_option(new_option(nil))}
  end

  # The bonus currently shown for a sheet item: the submitted param while
  # editing, the saved bonus otherwise.
  defp bonus_value(form, slug) do
    case form[:bonuses].value do
      %{} = bonuses -> Map.get(bonuses, slug, "")
      _ -> ""
    end
  end

  defp upload_error(:too_large), do: dgettext("management", "The image is too large (max 5 MB)")
  defp upload_error(:not_accepted), do: dgettext("management", "Unsupported file type")
  defp upload_error(:too_many_files), do: dgettext("management", "Only one image is allowed")

  defp upload_error(other),
    do: dgettext("management", "Upload error: %{inspect_other}", inspect_other: inspect(other))

  @impl true
  def render(assigns) do
    image_errors =
      upload_errors(assigns.uploads.image) ++
        Enum.flat_map(assigns.uploads.image.entries, &upload_errors(assigns.uploads.image, &1))

    assigns = assign(assigns, :image_errors, Enum.map(image_errors, &upload_error/1))

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
      <.gm_header story={@current_story} /> <.gm_tabs story={@current_story} tab="origins" />
      <div class="mt-6 grid gap-6 xl:grid-cols-[1fr_26rem]">
        <section id="origin-groups" class="space-y-4">
          <p :if={@groups == []} id="origin-groups-empty" class="text-sm text-base-content/60">
            {dgettext(
              "management",
              "No origin groups yet: add one (e.g. \"Race\" or \"Class\") to let players pick it at character creation."
            )}
          </p>

          <article
            :for={group <- @groups}
            id={"origin-group-#{group.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4 transition hover:border-secondary/40"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h3 class="flex items-center gap-2 font-semibold text-primary">
                  {group.name}
                  <span :if={group.required} class="badge badge-soft badge-sm badge-warning">
                    {dgettext("management", "Required")}
                  </span>
                </h3>

                <p :if={group.description} class="mt-1 text-sm text-base-content/70">
                  {group.description}
                </p>
              </div>

              <div class="flex shrink-0 gap-1">
                <button
                  id={"new-option-#{group.id}"}
                  phx-click="new_option"
                  phx-value-group={group.id}
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-primary"
                  title={dgettext("management", "Add option")}
                >
                  <.icon name="hero-plus-circle" class="size-4" />
                </button>

                <button
                  id={"edit-origin-group-#{group.id}"}
                  phx-click="edit_group"
                  phx-value-id={group.id}
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-secondary"
                  title={dgettext("management", "Edit")}
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>

                <button
                  id={"delete-origin-group-#{group.id}"}
                  phx-click="delete_group"
                  phx-value-id={group.id}
                  data-confirm={
                    dgettext(
                      "management",
                      "Delete this group, its options and the characters' choices?"
                    )
                  }
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-error"
                  title={dgettext("management", "Delete")}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>

            <p :if={group.options == []} class="mt-3 text-xs italic text-base-content/50">
              {dgettext("management", "No options yet.")}
            </p>

            <ul class="mt-3 grid gap-2 sm:grid-cols-2">
              <li
                :for={option <- group.options}
                id={"origin-option-#{option.id}"}
                class="flex gap-3 rounded-lg border border-secondary/15 bg-base-100/40 p-3 transition hover:border-primary/40"
              >
                <img
                  :if={option.image_path}
                  src={option.image_path}
                  alt=""
                  class="size-12 shrink-0 rounded object-cover"
                />
                <div class="min-w-0 flex-1">
                  <div class="flex items-center justify-between gap-2">
                    <span class="truncate font-semibold">{option.name}</span>
                    <span class="flex shrink-0 gap-1">
                      <button
                        id={"edit-origin-option-#{option.id}"}
                        phx-click="edit_option"
                        phx-value-id={option.id}
                        class="rounded p-0.5 text-base-content/60 transition-colors hover:text-secondary"
                        title={dgettext("management", "Edit")}
                      >
                        <.icon name="hero-pencil" class="size-3.5" />
                      </button>

                      <button
                        id={"delete-origin-option-#{option.id}"}
                        phx-click="delete_option"
                        phx-value-id={option.id}
                        data-confirm={
                          dgettext("management", "Delete this option? Characters lose it.")
                        }
                        class="rounded p-0.5 text-base-content/60 transition-colors hover:text-error"
                        title={dgettext("management", "Delete")}
                      >
                        <.icon name="hero-trash" class="size-3.5" />
                      </button>
                    </span>
                  </div>

                  <p
                    :if={Origins.bonus_label(option.bonuses)}
                    id={"origin-option-bonuses-#{option.id}"}
                    class="text-xs tabular-nums text-secondary"
                  >
                    {Origins.bonus_label(option.bonuses)}
                  </p>

                  <p
                    :if={option.requires_approval}
                    class="mt-1 flex items-center gap-1 text-xs text-warning"
                  >
                    <.icon name="hero-shield-exclamation-micro" class="size-3.5" /> {dgettext(
                      "management",
                      "Requires master approval"
                    )}
                  </p>
                </div>
              </li>
            </ul>
          </article>
        </section>

        <div class="space-y-6">
          <section class="rounded-xl border border-secondary/20 bg-base-200/80 p-5">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @group.id,
                do: dgettext("management", "Edit origin group"),
                else: dgettext("management", "New origin group")}
            </h2>

            <.form
              for={@group_form}
              id="origin-group-form"
              phx-change="validate_group"
              phx-submit="save_group"
              class="mt-4"
            >
              <.input
                field={@group_form[:name]}
                type="text"
                label={dgettext("management", "Name")}
                required
              />
              <.input
                field={@group_form[:description]}
                type="textarea"
                label={dgettext("management", "Description")}
                rows="2"
              />
              <div class="grid grid-cols-2 gap-3">
                <.input
                  field={@group_form[:position]}
                  type="number"
                  label={dgettext("management", "Position")}
                  min="0"
                />
                <.input
                  field={@group_form[:required]}
                  type="checkbox"
                  label={dgettext("management", "Required at creation")}
                />
              </div>

              <div class="flex gap-2">
                <.button id="save-origin-group" phx-disable-with={dgettext("management", "Saving...")}>
                  {if @group.id,
                    do: dgettext("management", "Update group"),
                    else: dgettext("management", "Add group")}
                </.button>

                <.button
                  :if={@group.id}
                  type="button"
                  id="cancel-origin-group"
                  phx-click="cancel_group"
                >
                  {dgettext("management", "Cancel")}
                </.button>
              </div>
            </.form>
          </section>

          <section
            :if={@groups != []}
            class="rounded-xl border border-secondary/20 bg-base-200/80 p-5"
          >
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @option.id,
                do: dgettext("management", "Edit origin option"),
                else: dgettext("management", "New origin option")}
            </h2>

            <.form
              for={@option_form}
              id="origin-option-form"
              phx-change="validate_option"
              phx-submit="save_option"
              class="mt-4"
            >
              <.input
                field={@option_form[:group_id]}
                type="select"
                label={dgettext("management", "Group")}
                prompt={dgettext("management", "Choose a group")}
                options={Enum.map(@groups, &{&1.name, &1.id})}
              />
              <.input
                field={@option_form[:name]}
                type="text"
                label={dgettext("management", "Name")}
                required
              />
              <.input
                field={@option_form[:description]}
                type="textarea"
                label={dgettext("management", "Description (Markdown)")}
                rows="5"
              />
              <div phx-drop-target={@uploads.image.ref} class="mb-2 space-y-2">
                <label for={@uploads.image.ref} class="console-label">{dgettext(
                  "management",
                  "Image (optional)"
                )}</label>
                <div class="flex flex-wrap items-center gap-3">
                  <img
                    :if={@option.image_path && @uploads.image.entries == []}
                    id="origin-option-image"
                    src={@option.image_path}
                    alt=""
                    class="size-14 rounded object-cover"
                  />
                  <button
                    :if={@option.image_path && @uploads.image.entries == []}
                    type="button"
                    id="remove-origin-option-image"
                    phx-click="remove_image"
                    class="text-xs text-error hover:underline"
                  >
                    {dgettext("management", "Remove")}
                  </button>

                  <div :for={entry <- @uploads.image.entries} class="flex items-center gap-2">
                    <.live_img_preview entry={entry} class="size-14 rounded object-cover" />
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      class="text-xs text-error hover:underline"
                    >
                      {dgettext("management", "Remove")}
                    </button>
                  </div>

                  <.live_file_input
                    upload={@uploads.image}
                    class="file-input file-input-secondary console-field w-full max-w-xs"
                  />
                </div>

                <.error :for={error <- @image_errors}>{error}</.error>
              </div>

              <fieldset
                id="origin-option-bonuses"
                class="mt-2 rounded-lg border border-secondary/20 p-3"
              >
                <legend class="px-1 text-xs font-bold uppercase tracking-wider text-secondary">
                  {dgettext("management", "Sheet bonuses")}
                </legend>

                <p class="mb-2 text-xs text-base-content/60">
                  {dgettext(
                    "management",
                    "Added to the character's values in formulas, trackers and dice (may exceed the item maximum). Leave blank for no bonus; negative values are allowed."
                  )}
                </p>

                <p :if={@items == []} class="text-xs text-warning">
                  {dgettext("management", "Define sheet items in the Sheet tab to give bonuses.")}
                </p>

                <div class="grid grid-cols-2 gap-x-3">
                  <.input
                    :for={item <- @items}
                    type="number"
                    id={"option-bonus-#{item.slug}"}
                    name={"option[bonuses][#{item.slug}]"}
                    value={bonus_value(@option_form, item.slug)}
                    label={item.name}
                  />
                </div>

                <.error :for={error <- @option_form[:bonuses].errors}>
                  {translate_error(error)}
                </.error>
              </fieldset>

              <div class="mt-3 grid grid-cols-2 gap-3">
                <.input
                  field={@option_form[:position]}
                  type="number"
                  label={dgettext("management", "Position")}
                  min="0"
                />
                <.input
                  field={@option_form[:requires_approval]}
                  type="checkbox"
                  label={dgettext("management", "Requires master approval")}
                />
              </div>

              <div class="flex gap-2">
                <.button
                  id="save-origin-option"
                  phx-disable-with={dgettext("management", "Saving...")}
                >
                  {if @option.id,
                    do: dgettext("management", "Update option"),
                    else: dgettext("management", "Add option")}
                </.button>

                <.button
                  :if={@option.id}
                  type="button"
                  id="cancel-origin-option"
                  phx-click="cancel_option"
                >
                  {dgettext("management", "Cancel")}
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
