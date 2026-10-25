defmodule TannhauserGateWeb.GmLive do
  @moduledoc """
  Dashboard where the GDR admin (or a platform admin) configures the GDR:
  general info, theme, character sheet, jobs, balances, map, forum sections and
  masters. The guide, zones and periodic actions have their own LiveViews
  (`GmLive.Guide`, `GmLive.Zones`, `GmLive.Actions`) sharing `GmNav`.
  Masters narrate the GDR from `TannhauserGateWeb.MasterLive`.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav
  alias TannhauserGateWeb.GmNav

  alias TannhauserGate.{
    Bank,
    Characters,
    Dice,
    Directory,
    Forum,
    Guilds,
    Modules,
    Sheet,
    Stories,
    Trackers,
    Zones
  }

  alias TannhauserGate.Bank.Job
  alias TannhauserGate.Characters.State
  alias TannhauserGate.Forum.Section
  alias TannhauserGate.Sheet.Item
  alias TannhauserGate.Stories.{Location, StoryMaster}
  alias TannhauserGate.Trackers.Tracker

  @impl true
  def mount(_params, _session, socket) do
    # Master rows are keyed by user, like the users they used to be.
    {:ok,
     socket
     |> stream_configure(:masters, dom_id: &"masters-#{&1.user_id}")
     |> allow_upload(:banner,
       accept: Directory.banner_extensions(),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "general"

    visible = for {key, _, :core} <- GmNav.visible_tabs(socket.assigns.current_story), do: key

    if tab in visible do
      {:noreply,
       socket
       |> assign(:tab, tab)
       |> assign(:page_title, dgettext("management", "GM dashboard"))
       |> load(tab)}
    else
      {:noreply, push_patch(socket, to: ~p"/g/#{socket.assigns.current_story}/gm")}
    end
  end

  defp story(socket), do: socket.assigns.current_story

  defp load(socket, "general"), do: assign_story_form(socket, story(socket))
  defp load(socket, "theme"), do: assign_story_form(socket, story(socket))
  defp load(socket, "esiti"), do: assign_story_form(socket, story(socket))
  defp load(socket, "modules"), do: assign(socket, :modules, Modules.all())

  defp load(socket, "map"),
    do: socket |> assign_story_form(story(socket)) |> assign_guilds() |> reload_locations()

  defp load(socket, "chat") do
    story = story(socket)
    # Show the defaults in the form when the GDR never configured its dice.
    story = if story.dice_config, do: story, else: %{story | dice_config: %Dice.Config{}}

    socket
    |> assign_story_form(story)
    |> assign(:trackers, Trackers.list_trackers(story))
  end

  defp load(socket, "sheet") do
    socket
    |> assign(:items, Sheet.list_items(story(socket)))
    |> assign_item_form(%Item{})
  end

  defp load(socket, "creation") do
    story = story(socket)

    socket
    |> assign(:items_by_kind, Sheet.items_by_kind(story))
    |> assign(:slugs, Sheet.slugs(story))
    |> assign(
      :category_forms,
      Map.new(Sheet.categories(story), fn {kind, category} ->
        {kind, category_form(Sheet.change_category(category), kind)}
      end)
    )
  end

  defp load(socket, "trackers") do
    socket
    |> assign(:trackers, Trackers.list_trackers(story(socket)))
    |> assign(:slugs, Sheet.slugs(story(socket)))
    |> assign_tracker_form(%Tracker{story_id: story(socket).id})
  end

  defp load(socket, "states") do
    socket
    |> assign(:states, Characters.list_states(story(socket)))
    |> assign_state_form(%State{})
  end

  defp load(socket, "jobs") do
    socket
    |> assign(:jobs, Bank.list_jobs(story(socket)))
    |> assign_job_form(%Job{})
  end

  defp load(socket, "balances") do
    socket
    |> assign(:characters, Characters.list_story_characters(story(socket).id))
    |> assign(:adjust_form, to_form(%{"amount" => "", "note" => ""}, as: :adjust))
  end

  defp load(socket, "forum") do
    socket
    |> assign_guilds()
    |> assign(:sections, Forum.list_sections(story(socket)))
    |> assign_section_form(%Section{})
  end

  defp load(socket, "masters") do
    masters = Stories.list_master_rows(story(socket))

    socket
    |> assign(:masters_empty?, masters == [])
    |> assign(:master_form, to_form(%{"username" => ""}, as: :master))
    |> stream(:masters, masters, reset: true)
  end

  # The guilds for guild forum sections and guild rooms (guilds module).
  defp assign_guilds(socket) do
    story = story(socket)
    on? = Guilds.enabled?(story)

    socket
    |> assign(:guilds_on?, on?)
    |> assign(:guilds, if(on?, do: Guilds.list_guilds(story), else: []))
  end

  defp guild_name(guilds, guild_id) do
    case Enum.find(guilds, &(&1.id == guild_id)) do
      nil -> nil
      guild -> guild.name
    end
  end

  defp section_visibilities(guilds_on?, section) do
    Section.visibilities()
    |> Enum.filter(&(&1 != "guild" or guilds_on? or section.visibility == "guild"))
    |> Enum.map(&{Forum.visibility_label(&1), &1})
  end

  defp apply_banner(story, nil), do: {:ok, story}
  defp apply_banner(story, path), do: Stories.set_banner(story, path)

  defp assign_story_form(socket, story) do
    assign(socket, :story_form, to_form(Stories.change_story_as_gm(story), as: :story))
  end

  defp assign_item_form(socket, item),
    do:
      socket
      |> assign(:item, item)
      |> assign(:item_form, to_form(Sheet.change_item(item), as: :item))

  defp category_form(changeset, kind),
    do: to_form(changeset, as: :category, id: "category-#{kind}")

  defp assign_tracker_form(socket, tracker) do
    socket
    |> assign(:tracker, tracker)
    |> assign(:tracker_form, to_form(Trackers.change_tracker(tracker), as: :tracker))
  end

  defp assign_state_form(socket, state),
    do:
      socket
      |> assign(:state, state)
      |> assign(:state_form, to_form(Characters.change_state(state), as: :state))

  defp assign_section_form(socket, section),
    do:
      socket
      |> assign(:section, section)
      |> assign(:section_form, to_form(Forum.change_section(section), as: :section))

  defp assign_job_form(socket, job),
    do: socket |> assign(:job, job) |> assign(:job_form, to_form(Bank.change_job(job), as: :job))

  defp assign_location_form(socket, location) do
    socket
    |> assign(:location, location)
    |> assign(:location_form, to_form(Stories.change_location(location), as: :location))
  end

  defp reload_locations(socket) do
    socket
    |> assign(:locations, Stories.list_locations(story(socket)))
    |> assign(:zones, Zones.list_zones(story(socket)))
    |> assign_location_form(%Location{})
  end

  ## Story (general / theme / map)

  @impl true
  def handle_event("validate_story", %{"story" => params}, socket) do
    changeset = Stories.change_story_as_gm(story(socket), params)
    {:noreply, assign(socket, :story_form, to_form(changeset, as: :story, action: :validate))}
  end

  def handle_event("preview_theme", %{"theme" => theme}, socket) do
    params = Map.put(socket.assigns.story_form.params, "theme", theme)
    handle_event("validate_story", %{"story" => params}, socket)
  end

  def handle_event("reset_theme", _, socket) do
    params =
      socket.assigns.story_form.params
      |> Map.put("theme_overrides", %{})
      |> Map.put("control_style", %{})

    handle_event("validate_story", %{"story" => params}, socket)
  end

  def handle_event("save_story", %{"story" => params}, socket) do
    banner =
      socket
      |> consume_uploaded_entries(:banner, fn %{path: path}, entry ->
        {:ok, Directory.store_banner(path, entry.client_name)}
      end)
      |> List.first()

    with {:ok, banner_path} <- banner || {:ok, nil},
         {:ok, updated} <- Stories.update_story_as_gm(story(socket), params),
         {:ok, updated} <- apply_banner(updated, banner_path) do
      {:noreply,
       socket
       |> assign(:current_story, updated)
       |> put_flash(:info, dgettext("management", "GDR updated"))
       |> assign_story_form(updated)}
    else
      {:error, :invalid_image} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("management", "The banner must be a PNG, JPEG or WebP image.")
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :story_form, to_form(changeset, as: :story))}
    end
  end

  def handle_event("cancel_banner", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :banner, ref)}

  def handle_event("remove_banner", _, socket) do
    {:ok, updated} = Stories.set_banner(story(socket), nil)

    {:noreply,
     socket
     |> assign(:current_story, updated)
     |> put_flash(:info, dgettext("management", "Banner removed"))}
  end

  ## Modules

  def handle_event("toggle_module", %{"key" => key}, socket) do
    story = story(socket)
    enabled? = not Stories.module_enabled?(story, key)

    case Stories.set_module_enabled(story, key, enabled?) do
      {:ok, updated} ->
        name = Modules.get(key).name

        {:noreply,
         socket
         |> assign(:current_story, updated)
         |> put_flash(
           :info,
           dgettext("management", "%{name} %{value}",
             name: name,
             value:
               if(enabled?,
                 do: dgettext("management", "enabled"),
                 else: dgettext("management", "disabled")
               )
           )
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("management", "Unknown module."))}
    end
  end

  ## Sheet items

  def handle_event("save_item", %{"item" => params}, socket) do
    item = socket.assigns.item

    result =
      if item.id,
        do: Sheet.update_item(item, params),
        else: Sheet.create_item(story(socket), params)

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, dgettext("management", "Saved")) |> load("sheet")}

      {:error, changeset} ->
        {:noreply, assign(socket, :item_form, to_form(changeset, as: :item))}
    end
  end

  def handle_event("edit_item", %{"id" => id}, socket) do
    {:noreply, assign_item_form(socket, Sheet.get_item!(story(socket), id))}
  end

  def handle_event("delete_item", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Sheet.get_item!(id) |> Sheet.delete_item()
    {:noreply, load(socket, "sheet")}
  end

  def handle_event("cancel_item", _, socket), do: {:noreply, assign_item_form(socket, %Item{})}

  ## Creation budgets and XP costs

  def handle_event("save_category", %{"kind" => kind, "category" => params}, socket) do
    if kind in Sheet.kinds() do
      case Sheet.save_category(story(socket), kind, params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             dgettext("management", "%{sheet_kind_label_kind} saved",
               sheet_kind_label_kind: Sheet.kind_label(kind)
             )
           )
           |> load("creation")}

        {:error, changeset} ->
          {:noreply,
           assign(
             socket,
             :category_forms,
             Map.put(socket.assigns.category_forms, kind, category_form(changeset, kind))
           )}
      end
    else
      {:noreply, socket}
    end
  end

  ## Trackers

  def handle_event("save_tracker", %{"tracker" => params}, socket) do
    tracker = socket.assigns.tracker

    result =
      if tracker.id,
        do: Trackers.update_tracker(tracker, params),
        else: Trackers.create_tracker(story(socket), params)

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, dgettext("management", "Tracker saved")) |> load("trackers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :tracker_form, to_form(changeset, as: :tracker))}
    end
  end

  def handle_event("edit_tracker", %{"id" => id}, socket) do
    {:noreply, assign_tracker_form(socket, Trackers.get_tracker!(story(socket), id))}
  end

  def handle_event("delete_tracker", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Trackers.get_tracker!(id) |> Trackers.delete_tracker()
    {:noreply, load(socket, "trackers")}
  end

  def handle_event("cancel_tracker", _, socket),
    do: {:noreply, assign_tracker_form(socket, %Tracker{story_id: story(socket).id})}

  ## Character states

  def handle_event("save_state", %{"state" => params}, socket) do
    state = socket.assigns.state

    result =
      if state.id,
        do: Characters.update_state(state, params),
        else: Characters.create_state(story(socket), params)

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, dgettext("management", "Saved")) |> load("states")}

      {:error, changeset} ->
        {:noreply, assign(socket, :state_form, to_form(changeset, as: :state))}
    end
  end

  def handle_event("edit_state", %{"id" => id}, socket) do
    {:noreply, assign_state_form(socket, Characters.get_state!(story(socket), id))}
  end

  def handle_event("delete_state", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Characters.get_state!(id) |> Characters.delete_state()
    {:noreply, load(socket, "states")}
  end

  def handle_event("cancel_state", _, socket),
    do: {:noreply, assign_state_form(socket, %State{})}

  ## Jobs

  def handle_event("save_job", %{"job" => params}, socket) do
    job = socket.assigns.job

    result =
      if job.id, do: Bank.update_job(job, params), else: Bank.create_job(story(socket), params)

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, dgettext("management", "Saved")) |> load("jobs")}

      {:error, changeset} ->
        {:noreply, assign(socket, :job_form, to_form(changeset, as: :job))}
    end
  end

  def handle_event("edit_job", %{"id" => id}, socket) do
    {:noreply, assign_job_form(socket, Bank.get_job!(story(socket), id))}
  end

  def handle_event("delete_job", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Bank.get_job!(id) |> Bank.delete_job()
    {:noreply, load(socket, "jobs")}
  end

  def handle_event("cancel_job", _, socket), do: {:noreply, assign_job_form(socket, %Job{})}

  ## Balances

  def handle_event("adjust", %{"character_id" => id, "adjust" => params}, socket) do
    character = Characters.get_character!(id)

    if character.story_id == story(socket).id do
      case Bank.adjust(character, params["amount"], params["note"]) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("management", "Balance updated"))
           |> load("balances")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Bank.error_message(reason))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("management", "That character is not in this GDR."))}
    end
  end

  ## Locations

  def handle_event("save_location", %{"location" => params}, socket) do
    location = socket.assigns.location

    result =
      if location.id,
        do: Stories.update_location(location, params),
        else: Stories.create_location(story(socket), params)

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, dgettext("management", "Saved")) |> reload_locations()}

      {:error, changeset} ->
        {:noreply, assign(socket, :location_form, to_form(changeset, as: :location))}
    end
  end

  def handle_event("edit_location", %{"id" => id}, socket) do
    {:noreply, assign_location_form(socket, own_location!(socket, id))}
  end

  def handle_event("delete_location", %{"id" => id}, socket) do
    {:ok, _} = socket |> own_location!(id) |> Stories.delete_location()
    {:noreply, reload_locations(socket)}
  end

  def handle_event("cancel_location", _, socket),
    do: {:noreply, assign_location_form(socket, %Location{})}

  ## Forum sections

  def handle_event("save_section", %{"section" => params}, socket) do
    section = socket.assigns.section

    result =
      if section.id,
        do: Forum.update_section(section, params),
        else: Forum.create_section(story(socket), params)

    case result do
      {:ok, _} ->
        message =
          if section.id,
            do: dgettext("management", "Section updated"),
            else: dgettext("management", "Section created")

        {:noreply, socket |> put_flash(:info, message) |> load("forum")}

      {:error, changeset} ->
        {:noreply, assign(socket, :section_form, to_form(changeset, as: :section))}
    end
  end

  def handle_event("edit_section", %{"id" => id}, socket) do
    section = Forum.get_section!(id)

    if section.story_id == story(socket).id,
      do: {:noreply, assign_section_form(socket, section)},
      else:
        {:noreply,
         put_flash(socket, :error, dgettext("management", "That section is not in this GDR."))}
  end

  def handle_event("cancel_section", _, socket),
    do: {:noreply, assign_section_form(socket, %Section{})}

  def handle_event("delete_section", %{"id" => id}, socket) do
    section = Forum.get_section!(id)

    if section.story_id == story(socket).id do
      {:ok, _} = Forum.delete_section(section)
      {:noreply, load(socket, "forum")}
    else
      {:noreply,
       put_flash(socket, :error, dgettext("management", "That section is not in this GDR."))}
    end
  end

  ## Masters

  def handle_event("add_master", %{"master" => %{"username" => username}}, socket) do
    case Stories.add_master(story(socket), username) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("management", "%{user_username} is now a master",
             user_username: user.username
           )
         )
         |> load("masters")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Stories.master_error_message(reason))
         |> assign(:master_form, to_form(%{"username" => username}, as: :master))}
    end
  end

  def handle_event("toggle_permission", %{"user_id" => user_id, "perm" => perm} = params, socket) do
    permission =
      Enum.find(StoryMaster.permissions(), &(Atom.to_string(&1) == perm))

    with true <- permission != nil,
         {user_id, ""} <- Integer.parse(user_id),
         {:ok, row} <-
           Stories.set_master_permission(
             story(socket),
             user_id,
             permission,
             params["value"] == "true"
           ) do
      row = TannhauserGate.Repo.preload(row, :user)
      {:noreply, stream_insert(socket, :masters, row)}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("management", "That master does not exist in this GDR.")
         )}
    end
  end

  def handle_event("remove_master", %{"id" => id}, socket) do
    case Stories.remove_master(story(socket), id) do
      :ok ->
        {:noreply,
         socket |> put_flash(:info, dgettext("management", "Master removed")) |> load("masters")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Stories.master_error_message(reason))}
    end
  end

  defp own_location!(socket, id) do
    location = Stories.get_location!(id)
    true = location.story_id == story(socket).id
    location
  end

  ## Rendering

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
      <.gm_header story={@current_story} /> <.gm_tabs story={@current_story} tab={@tab} />
      <div class="mt-6">
        <.general_tab :if={@tab == "general"} {assigns} />
        <.modules_tab :if={@tab == "modules"} {assigns} />
        <.theme_tab :if={@tab == "theme"} {assigns} /> <.sheet_tab :if={@tab == "sheet"} {assigns} />
        <.creation_tab :if={@tab == "creation"} {assigns} />
        <.trackers_tab :if={@tab == "trackers"} {assigns} />
        <.states_tab :if={@tab == "states"} {assigns} /> <.jobs_tab :if={@tab == "jobs"} {assigns} />
        <.balances_tab :if={@tab == "balances"} {assigns} />
        <.map_tab :if={@tab == "map"} {assigns} /> <.chat_tab :if={@tab == "chat"} {assigns} />
        <.forum_tab :if={@tab == "forum"} {assigns} />
        <.masters_tab :if={@tab == "masters"} {assigns} />
        <.esiti_tab :if={@tab == "esiti"} {assigns} />
      </div>
    </Layouts.app>
    """
  end

  defp panel(assigns) do
    ~H"""
    <div class="max-w-3xl rounded-xl border border-secondary/20 bg-base-200/80 p-6">
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp general_tab(assigns) do
    ~H"""
    <.panel>
      <.form
        for={@story_form}
        id="general-form"
        phx-change="validate_story"
        phx-submit="save_story"
      >
        <.input
          field={@story_form[:name]}
          type="text"
          label={dgettext("management", "Name")}
          required
        />
        <.input
          field={@story_form[:summary]}
          type="textarea"
          label={dgettext("management", "Summary")}
          rows="3"
        />
        <p class="mb-2 text-sm text-base-content/70">
          {dgettext("management", "The background, rules and customs of the world are written in the")} <.link
            id="general-guide-link"
            navigate={~p"/g/#{@current_story}/gm/guide"}
            class="link link-primary"
          >
            {dgettext("management", "guide")}
          </.link>.
        </p>

        <.input
          field={@story_form[:currency_name]}
          type="text"
          label={dgettext("management", "Currency name")}
        />
        <.input
          field={@story_form[:pay_interval_hours]}
          type="number"
          label={dgettext("management", "Pay interval (hours)")}
          min="1"
        />
        <.input
          :if={Stories.module_enabled?(@current_story, :guilds)}
          field={@story_form[:max_guilds_per_character]}
          type="number"
          label={dgettext("management", "Maximum guilds per character")}
          min="1"
          max="20"
        />
        <fieldset id="character-limit-settings" class="mt-2 border-t border-secondary/20 pt-4">
          <legend class="text-sm font-semibold text-base-content/80">
            {dgettext("management", "Characters per player")}
          </legend>

          <p class="mb-2 text-xs text-base-content/60">
            {dgettext(
              "management",
              "How many characters each player can create (drafts and rejected ones count; NPCs never do). With more than one, players switch the character they are playing from the navigation."
            )}
          </p>

          <.input
            field={@story_form[:max_characters_per_user]}
            type="number"
            label={dgettext("management", "Maximum characters per player")}
            min="1"
            max="10"
          />
          <.input
            field={@story_form[:block_alt_transfers]}
            type="checkbox"
            label={
              dgettext(
                "management",
                "Block money transfers and item gifts between characters of the same player"
              )
            }
          />
          <.input
            field={@story_form[:block_alt_mail]}
            type="checkbox"
            label={dgettext("management", "Block letters between characters of the same player")}
          />
          <.input
            :if={Stories.module_enabled?(@current_story, :chat_rp)}
            field={@story_form[:block_alt_whispers]}
            type="checkbox"
            label={dgettext("management", "Block whispers between characters of the same player")}
          />
        </fieldset>

        <.input
          field={@story_form[:status]}
          type="select"
          label={dgettext("management", "Status")}
          options={[
            {dgettext("management", "Draft (only you and your masters)"), "draft"},
            {dgettext("management", "Published"), "published"}
          ]}
        />
        <.listing_fieldset
          story_form={@story_form}
          current_story={@current_story}
          uploads={@uploads}
        />
        <fieldset id="sheet-template-settings" class="mt-2 border-t border-secondary/20 pt-4">
          <legend class="text-sm font-semibold text-base-content/80">
            {dgettext("management", "Character sheet template")}
          </legend>

          <p class="mb-2 text-xs text-base-content/60">
            {dgettext(
              "management",
              "Markdown prefilled in the background of new characters (e.g. headings for appearance, past and goals). Players edit it freely."
            )}
          </p>

          <.input
            field={@story_form[:sheet_template]}
            type="textarea"
            label={dgettext("management", "Sheet template (Markdown)")}
            rows="6"
          />
        </fieldset>

        <fieldset id="community-link-settings" class="mt-2 border-t border-secondary/20 pt-4">
          <legend class="text-sm font-semibold text-base-content/80">
            {dgettext("management", "Community link")}
          </legend>

          <p class="mb-2 text-xs text-base-content/60">
            {dgettext(
              "management",
              "An external community for the players (e.g. a Discord server), shown in the GDR navigation."
            )}
          </p>

          <.input
            field={@story_form[:community_url]}
            type="url"
            label={dgettext("management", "Community URL")}
            placeholder={dgettext("management", "https://discord.gg/...")}
          />
          <.input
            field={@story_form[:community_label]}
            type="text"
            label={dgettext("management", "Community label")}
            placeholder={dgettext("management", "Community")}
          />
        </fieldset>

        <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
          "management",
          "Save"
        )}</.button>
      </.form>
    </.panel>
    """
  end

  defp listing_fieldset(assigns) do
    banner_errors =
      upload_errors(assigns.uploads.banner) ++
        Enum.flat_map(assigns.uploads.banner.entries, &upload_errors(assigns.uploads.banner, &1))

    assigns =
      assigns
      |> assign(:genres, List.wrap(assigns.story_form[:genres].value))
      |> assign(:banner_errors, Enum.map(banner_errors, &banner_error/1))

    ~H"""
    <fieldset id="directory-listing-settings" class="mt-2 border-t border-secondary/20 pt-4">
      <legend class="text-sm font-semibold text-base-content/80">
        {dgettext("management", "Directory listing")}
      </legend>

      <p class="mb-2 text-xs text-base-content/60">
        {dgettext(
          "management",
          "How the GDR appears in the portal directory. The lifecycle is shown as a badge and does not change who can enter: use the status below for that."
        )}
      </p>

      <.input
        field={@story_form[:pitch]}
        type="text"
        label={dgettext("management", "Pitch (a one-line tagline)")}
        maxlength="160"
        placeholder={dgettext("management", "Rain, neon and the ghosts in the machine.")}
      />
      <div class="mb-3">
        <span class="label console-label mb-1">{dgettext("management", "Genres (up to 3)")}</span>
        <input type="hidden" name={@story_form[:genres].name <> "[]"} value="" />
        <div id="listing-genres" class="flex flex-wrap gap-2">
          <label
            :for={{value, label} <- Directory.genres()}
            id={"listing-genre-#{value}"}
            class="cursor-pointer select-none rounded-full border border-secondary/30 px-3 py-1 text-xs text-base-content/70 transition hover:border-primary/60 hover:text-base-content has-checked:border-primary has-checked:bg-primary/15 has-checked:text-primary has-focus-visible:ring-2 has-focus-visible:ring-primary/50"
          >
            <input
              type="checkbox"
              name={@story_form[:genres].name <> "[]"}
              value={value}
              checked={value in @genres}
              class="sr-only"
            /> {label}
          </label>
        </div>

        <.error :for={msg <- Enum.map(@story_form[:genres].errors, &translate_error/1)}>
          {msg}
        </.error>
      </div>

      <div class="grid gap-x-4 sm:grid-cols-2">
        <.input
          field={@story_form[:lifecycle]}
          type="select"
          label={dgettext("management", "Lifecycle")}
          options={for {value, label} <- Directory.lifecycles(), do: {label, value}}
        />
        <.input
          field={@story_form[:content_rating]}
          type="select"
          label={dgettext("management", "Content rating")}
          options={for {value, label} <- Directory.content_ratings(), do: {label, value}}
        />
      </div>

      <div id="listing-banner" phx-drop-target={@uploads.banner.ref} class="mb-3 space-y-2">
        <label for={@uploads.banner.ref} class="label console-label">
          {dgettext("management", "Banner (PNG, JPEG or WebP, about 1200×400)")}
        </label>

        <div class="flex flex-wrap items-center gap-3">
          <img
            :if={@current_story.banner_path && @uploads.banner.entries == []}
            id="listing-banner-image"
            src={@current_story.banner_path}
            alt=""
            class="h-16 w-48 rounded-lg object-cover"
          />
          <button
            :if={@current_story.banner_path && @uploads.banner.entries == []}
            type="button"
            id="remove-listing-banner"
            phx-click="remove_banner"
            class="text-xs text-error hover:underline"
          >
            {dgettext("management", "Remove")}
          </button>

          <div :for={entry <- @uploads.banner.entries} class="flex items-center gap-2">
            <.live_img_preview entry={entry} class="h-16 w-48 rounded-lg object-cover" />
            <button
              type="button"
              phx-click="cancel_banner"
              phx-value-ref={entry.ref}
              class="text-xs text-error hover:underline"
            >
              {dgettext("management", "Remove")}
            </button>
          </div>

          <.live_file_input
            upload={@uploads.banner}
            class="file-input file-input-secondary console-field w-full max-w-xs"
          />
        </div>

        <.error :for={error <- @banner_errors}>{error}</.error>
      </div>
    </fieldset>
    """
  end

  defp banner_error(:too_large), do: dgettext("management", "The banner is too large (max 5 MB)")

  defp banner_error(:not_accepted),
    do: dgettext("management", "The banner must be a PNG, JPEG or WebP image")

  defp banner_error(:too_many_files), do: dgettext("management", "Only one banner is allowed")

  defp banner_error(other),
    do: dgettext("management", "Upload error: %{inspect_other}", inspect_other: inspect(other))

  defp modules_tab(assigns) do
    ~H"""
    <.panel>
      <p class="mb-4 text-sm text-base-content/70">
        {dgettext(
          "management",
          "Turn on the optional features your GDR uses. Disabled modules are hidden from the players and their data is kept, so you can turn them back on at any time."
        )}
      </p>

      <ul id="modules-list" class="divide-y divide-secondary/15">
        <li
          :for={module <- @modules}
          id={"module-#{module.key}"}
          class="flex items-start gap-4 py-3"
        >
          <.icon name={module.icon} class="mt-0.5 size-5 shrink-0 text-secondary" />
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold">{module.name}</p>

            <p class="text-xs text-base-content/60">{module.description}</p>
          </div>

          <button
            type="button"
            id={"module-toggle-#{module.key}"}
            role="switch"
            aria-checked={to_string(Stories.module_enabled?(@current_story, module.key))}
            aria-label={dgettext("management", "Enable %{module_name}", module_name: module.name)}
            phx-click="toggle_module"
            phx-value-key={module.key}
            class={[
              "relative inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border transition-colors duration-200",
              if(Stories.module_enabled?(@current_story, module.key),
                do: "border-primary bg-primary/30",
                else: "border-secondary/40 bg-base-300"
              )
            ]}
          >
            <span class={[
              "inline-block size-4 rounded-full shadow transition-transform duration-200",
              if(Stories.module_enabled?(@current_story, module.key),
                do: "translate-x-6 bg-primary",
                else: "translate-x-1 bg-base-content/50"
              )
            ]} />
          </button>
        </li>
      </ul>
    </.panel>
    """
  end

  defp theme_tab(assigns) do
    ~H"""
    <.appearance_editor form={@story_form} />
    """
  end

  defp sheet_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @item.id,
            do: dgettext("management", "Edit item"),
            else: dgettext("management", "New item")}
        </h2>

        <.form for={@item_form} id="item-form" phx-submit="save_item">
          <.input
            field={@item_form[:kind]}
            type="select"
            label={dgettext("management", "Kind")}
            options={[
              {dgettext("management", "Attribute"), "attribute"},
              {dgettext("management", "Skill"), "skill"},
              {dgettext("management", "Power"), "power"}
            ]}
          />
          <.input
            field={@item_form[:name]}
            type="text"
            label={dgettext("management", "Name")}
            required
          />
          <.input
            field={@item_form[:slug]}
            type="text"
            label={dgettext("management", "Key for formulas")}
            placeholder={dgettext("management", "Derived from the name, e.g. blood_potency")}
          />
          <.input
            field={@item_form[:description]}
            type="textarea"
            label={dgettext("management", "Description")}
            rows="2"
          />
          <div class="grid grid-cols-3 gap-3">
            <.input
              field={@item_form[:min_value]}
              type="number"
              label={dgettext("management", "Min")}
            />
            <.input
              field={@item_form[:max_value]}
              type="number"
              label={dgettext("management", "Max")}
            />
            <.input
              field={@item_form[:position]}
              type="number"
              label={dgettext("management", "Order")}
            />
          </div>

          <div class="flex gap-3">
            <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Save item"
            )}</.button>
            <.link :if={@item.id} id="cancel-item" phx-click="cancel_item" class="self-center">
              {dgettext("management", "Cancel")}
            </.link>
          </div>
        </.form>
      </.panel>

      <.panel>
        <div :for={kind <- Sheet.kinds()} id={"items-#{kind}"} class="mb-4">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {Sheet.kind_label(kind)}
          </h2>

          <ul class="mt-1 divide-y divide-secondary/10">
            <li
              :for={i <- Enum.filter(@items, &(&1.kind == kind))}
              id={"item-#{i.id}"}
              class="flex items-center justify-between gap-2 py-1.5 text-sm"
            >
              <span>
                {i.name} <span class="text-base-content/50">{i.min_value}–{i.max_value}</span>
                <code class="ml-1 text-xs text-secondary/70">{i.slug}</code>
              </span>

              <span class="flex gap-3">
                <.link phx-click="edit_item" phx-value-id={i.id}>{dgettext("management", "Edit")}</.link>
                <.link
                  phx-click="delete_item"
                  phx-value-id={i.id}
                  data-confirm={
                    dgettext("management", "Delete this item? Character values for it are removed.")
                  }
                >
                  {dgettext("management", "Delete")}
                </.link>
              </span>
            </li>
          </ul>
        </div>
      </.panel>
    </div>
    """
  end

  defp creation_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Character creation and XP")}
        </h2>

        <p class="mt-1 text-sm text-base-content/70">
          {dgettext("management", "For each category choose how players build a new character:")}
          <strong>{dgettext("management", "free")}</strong> {dgettext(
            "management",
            "(any value within each item range), a"
          )}
          <strong>{dgettext("management", "points pool")}</strong> {dgettext(
            "management",
            "to spend above the starting value, or a"
          )}
          <strong>{dgettext("management", "distribution")}</strong> {dgettext(
            "management",
            "of values to assign (e.g."
          )} <code>4,3,3,2,2,2,1</code>{dgettext(
            "management",
            "; the other items keep the starting value). Masters creating NPCs or editing characters are never limited."
          )}
        </p>

        <p class="mt-2 text-sm text-base-content/70">
          {dgettext(
            "management",
            "The XP cost formula gives the price to raise an item by one point. It can use"
          )} <code>current</code>, <code>next</code>{dgettext("management", ", whole numbers,")} <code>+ - * /</code>, <code>min(a, b)</code>, <code>max(a, b)</code>{dgettext(
            "management",
            ", parentheses and the item keys. Leave it empty to forbid raising that category with XP."
          )}
        </p>

        <p :if={@slugs != []} id="formula-keys" class="mt-2 text-xs text-base-content/60">
          {dgettext("management", "Item keys:")}
          <code :for={slug <- @slugs} class="mr-2 text-secondary">{slug}</code>
        </p>
      </.panel>

      <div class="grid gap-6 lg:grid-cols-3">
        <.panel :for={kind <- Sheet.kinds()}>
          <h3 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {Sheet.kind_label(kind)}
            <span class="ml-1 text-xs font-normal normal-case tracking-normal text-base-content/50">
              {dgettext("management", "%{length__items_by_kind_kind} items",
                length__items_by_kind_kind: length(@items_by_kind[kind])
              )}
            </span>
          </h3>

          <.form
            for={@category_forms[kind]}
            id={"category-form-#{kind}"}
            phx-submit="save_category"
          >
            <input type="hidden" name="kind" value={kind} />
            <.input
              field={@category_forms[kind][:creation_mode]}
              type="select"
              label={dgettext("management", "Creation")}
              options={[
                {dgettext("management", "Free"), "free"},
                {dgettext("management", "Points pool"), "points"},
                {dgettext("management", "Distribution"), "distribution"}
              ]}
            />
            <.input
              field={@category_forms[kind][:starting_value]}
              type="number"
              label={dgettext("management", "Starting value")}
            />
            <.input
              field={@category_forms[kind][:creation_points]}
              type="number"
              label={dgettext("management", "Points pool (points mode)")}
              min="0"
            />
            <.input
              field={@category_forms[kind][:creation_distribution]}
              type="text"
              label={dgettext("management", "Values to assign (distribution mode)")}
              placeholder={dgettext("management", "4,3,3,2,2,2,1")}
            />
            <.input
              field={@category_forms[kind][:xp_cost_formula]}
              type="text"
              label={dgettext("management", "XP cost formula")}
              placeholder={dgettext("management", "next * 5")}
            />
            <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Save %{string_downcase_sheet_kind_label_kind}",
              string_downcase_sheet_kind_label_kind: String.downcase(Sheet.kind_label(kind))
            )}</.button>
          </.form>
        </.panel>
      </div>
    </div>
    """
  end

  defp trackers_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @tracker.id,
            do: dgettext("management", "Edit tracker"),
            else: dgettext("management", "New tracker")}
        </h2>

        <p class="mt-1 text-sm text-base-content/60">
          {dgettext(
            "management",
            "Trackers are resources every character has, like health, willpower or hunger. The maximum is a number or a formula over the item keys (e.g."
          )} <code>stamina + 3</code>{dgettext("management", "). With damage types (e.g.")} <code>superficial, aggravated</code>{dgettext(
            "management",
            ") the tracker counts damage of each type instead of a single value."
          )}
        </p>

        <.form for={@tracker_form} id="tracker-form" phx-submit="save_tracker">
          <.input
            field={@tracker_form[:name]}
            type="text"
            label={dgettext("management", "Name")}
            required
          />
          <.input
            field={@tracker_form[:slug]}
            type="text"
            label={dgettext("management", "Key")}
            placeholder={dgettext("management", "Derived from the name, e.g. willpower")}
          />
          <.input
            field={@tracker_form[:max_formula]}
            type="text"
            label={dgettext("management", "Maximum (number or formula)")}
            placeholder={dgettext("management", "composure + resolve")}
            required
          />
          <.input
            field={@tracker_form[:damage_types]}
            type="text"
            label={dgettext("management", "Damage types (optional, comma separated)")}
            value={Enum.join(List.wrap(@tracker_form[:damage_types].value), ", ")}
            placeholder={dgettext("management", "superficial, aggravated")}
          />
          <div class="grid grid-cols-2 gap-3">
            <.input
              field={@tracker_form[:position]}
              type="number"
              label={dgettext("management", "Order")}
            />
          </div>

          <.input
            field={@tracker_form[:starts_full]}
            type="checkbox"
            label={dgettext("management", "Starts full (otherwise starts at 0)")}
          />
          <.input
            field={@tracker_form[:public]}
            type="checkbox"
            label={dgettext("management", "Visible to everyone on the public sheet")}
          />
          <p :if={@slugs != []} class="mb-3 text-xs text-base-content/60">
            {dgettext("management", "Item keys:")}
            <code :for={slug <- @slugs} class="mr-2 text-secondary">{slug}</code>
          </p>

          <div class="flex gap-3">
            <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Save tracker"
            )}</.button>
            <.link
              :if={@tracker.id}
              id="cancel-tracker"
              phx-click="cancel_tracker"
              class="self-center"
            >
              {dgettext("management", "Cancel")}
            </.link>
          </div>
        </.form>
      </.panel>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Trackers")}
        </h2>

        <p :if={@trackers == []} class="mt-2 text-sm text-base-content/60">
          {dgettext("management", "No trackers yet.")}
        </p>

        <ul id="trackers" class="mt-1 divide-y divide-secondary/10">
          <li
            :for={t <- @trackers}
            id={"tracker-#{t.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span>
              {t.name} <code class="ml-1 text-xs text-secondary/70">{t.slug}</code>
              <span class="block text-xs text-base-content/60">
                {dgettext("management", "max")} <code>{t.max_formula}</code>
                <span :if={t.damage_types != []}>· {Enum.join(t.damage_types, " / ")}</span>
                <span class="badge badge-xs badge-soft ml-1">
                  {if t.public,
                    do: dgettext("management", "public"),
                    else: dgettext("management", "private")}
                </span>
              </span>
            </span>

            <span class="flex gap-3">
              <.link id={"edit-tracker-#{t.id}"} phx-click="edit_tracker" phx-value-id={t.id}>
                {dgettext("management", "Edit")}
              </.link>

              <.link
                id={"delete-tracker-#{t.id}"}
                phx-click="delete_tracker"
                phx-value-id={t.id}
                data-confirm={
                  dgettext("management", "Delete this tracker? Every character loses its value.")
                }
              >
                {dgettext("management", "Delete")}
              </.link>
            </span>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end

  defp states_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @state.id,
            do: dgettext("management", "Edit state"),
            else: dgettext("management", "New state")}
        </h2>

        <p class="mt-1 text-sm text-base-content/60">
          {dgettext(
            "management",
            "Masters move characters between states. Characters in a state that cannot play (e.g. dead or in torpor) cannot speak in the chat rooms. New characters get the first state."
          )}
        </p>

        <.form for={@state_form} id="state-form" phx-submit="save_state">
          <.input
            field={@state_form[:name]}
            type="text"
            label={dgettext("management", "Name")}
            required
          />
          <.input
            field={@state_form[:can_play]}
            type="checkbox"
            label={dgettext("management", "Can play")}
          />
          <.input
            field={@state_form[:position]}
            type="number"
            label={dgettext("management", "Order")}
          />
          <div class="flex gap-3">
            <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Save state"
            )}</.button>
            <.link :if={@state.id} id="cancel-state" phx-click="cancel_state" class="self-center">
              {dgettext("management", "Cancel")}
            </.link>
          </div>
        </.form>
      </.panel>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "States")}
        </h2>

        <p :if={@states == []} class="mt-2 text-sm text-base-content/60">
          {dgettext("management", "No states: every approved character can play.")}
        </p>

        <ul id="states" class="mt-1 divide-y divide-secondary/10">
          <li
            :for={s <- @states}
            id={"state-#{s.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span>
              {s.name}
              <span class={[
                "badge badge-sm badge-soft ml-2",
                if(s.can_play, do: "badge-success", else: "badge-error")
              ]}>
                {if s.can_play,
                  do: dgettext("management", "plays"),
                  else: dgettext("management", "cannot play")}
              </span>
            </span>

            <span class="flex gap-3">
              <.link id={"edit-state-#{s.id}"} phx-click="edit_state" phx-value-id={s.id}>
                {dgettext("management", "Edit")}
              </.link>

              <.link
                id={"delete-state-#{s.id}"}
                phx-click="delete_state"
                phx-value-id={s.id}
                data-confirm={
                  dgettext(
                    "management",
                    "Delete this state? Its characters are left without a state."
                  )
                }
              >
                {dgettext("management", "Delete")}
              </.link>
            </span>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end

  defp jobs_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @job.id, do: dgettext("management", "Edit job"), else: dgettext("management", "New job")}
        </h2>

        <.form for={@job_form} id="job-form" phx-submit="save_job">
          <.input
            field={@job_form[:name]}
            type="text"
            label={dgettext("management", "Name")}
            required
          />
          <.input
            field={@job_form[:description]}
            type="textarea"
            label={dgettext("management", "Description")}
            rows="2"
          />
          <.input
            field={@job_form[:pay]}
            type="number"
            label={
              dgettext("management", "Pay (%{current_story_currency_name} per interval)",
                current_story_currency_name: @current_story.currency_name
              )
            }
            min="0"
          />
          <div class="flex gap-3">
            <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Save job"
            )}</.button>
            <.link :if={@job.id} id="cancel-job" phx-click="cancel_job" class="self-center">
              {dgettext("management", "Cancel")}
            </.link>
          </div>
        </.form>
      </.panel>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Jobs")}
        </h2>

        <p :if={@jobs == []} class="mt-2 text-sm text-base-content/60">
          {dgettext("management", "No jobs yet.")}
        </p>

        <ul class="mt-1 divide-y divide-secondary/10">
          <li
            :for={j <- @jobs}
            id={"job-row-#{j.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span>{j.name} <span class="text-base-content/50">{j.pay}</span></span>
            <span class="flex gap-3">
              <.link phx-click="edit_job" phx-value-id={j.id}>{dgettext("management", "Edit")}</.link>
              <.link
                phx-click="delete_job"
                phx-value-id={j.id}
                data-confirm={
                  dgettext("management", "Delete this job? Characters holding it become unemployed.")
                }
              >
                {dgettext("management", "Delete")}
              </.link>
            </span>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end

  defp balances_tab(assigns) do
    ~H"""
    <.panel>
      <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
        {dgettext("management", "Balances")}
      </h2>

      <p :if={@characters == []} class="mt-2 text-sm text-base-content/60">
        {dgettext("management", "No characters yet.")}
      </p>

      <div :for={c <- @characters} id={"balance-#{c.id}"} class="border-b border-secondary/10 py-3">
        <p class="font-semibold text-primary">
          {c.name}
          <span class="text-base-content/60">· {c.balance} {@current_story.currency_name}</span>
        </p>

        <form
          id={"adjust-form-#{c.id}"}
          phx-submit="adjust"
          class="mt-2 flex flex-wrap items-end gap-2"
        >
          <input type="hidden" name="character_id" value={c.id} />
          <input
            type="number"
            name="adjust[amount]"
            placeholder={dgettext("management", "+/- amount")}
            class="input input-sm console-field w-32"
            aria-label={dgettext("management", "Amount for %{c_name}", c_name: c.name)}
          />
          <input
            type="text"
            name="adjust[note]"
            placeholder={dgettext("management", "Note")}
            class="input input-sm console-field w-48"
            aria-label={dgettext("management", "Note for %{c_name}", c_name: c.name)}
          /> <.button class="btn btn-sm">{dgettext("management", "Apply")}</.button>
        </form>
      </div>
    </.panel>
    """
  end

  defp map_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <div class="space-y-6">
        <.panel>
          <.form for={@story_form} id="map-form" phx-submit="save_story">
            <.input
              field={@story_form[:map_svg]}
              type="textarea"
              label={dgettext("management", "Map SVG")}
              rows="6"
            />
            <div class="grid grid-cols-2 gap-3">
              <.input
                field={@story_form[:map_width]}
                type="number"
                label={dgettext("management", "Width")}
              />
              <.input
                field={@story_form[:map_height]}
                type="number"
                label={dgettext("management", "Height")}
              />
            </div>

            <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Save map"
            )}</.button>
          </.form>
        </.panel>

        <.panel>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {if @location.id,
              do: dgettext("management", "Edit room"),
              else: dgettext("management", "New room")}
          </h2>

          <.form for={@location_form} id="location-form" phx-submit="save_location">
            <.input
              field={@location_form[:name]}
              type="text"
              label={dgettext("management", "Name")}
              required
            />
            <.input
              field={@location_form[:description]}
              type="textarea"
              label={dgettext("management", "Description")}
              rows="2"
            />
            <.input
              field={@location_form[:area]}
              type="text"
              label={dgettext("management", "Map area (SVG path)")}
            />
            <.input
              field={@location_form[:color]}
              type="text"
              label={dgettext("management", "Color")}
            />
            <.input
              field={@location_form[:private]}
              type="checkbox"
              label={
                dgettext(
                  "management",
                  "Private (players book it for a time slot and invite characters)"
                )
              }
            />
            <.input
              field={@location_form[:zone_id]}
              type="select"
              label={dgettext("management", "Zone")}
              prompt={dgettext("management", "No zone")}
              options={Enum.map(@zones, &{&1.name, &1.id})}
            />
            <.input
              :if={@guilds_on?}
              field={@location_form[:guild_id]}
              type="select"
              label={dgettext("management", "Reserved to guild")}
              prompt={dgettext("management", "Open to everyone")}
              options={Enum.map(@guilds, &{&1.name, &1.id})}
            />
            <div class="flex gap-3">
              <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
                "management",
                "Save room"
              )}</.button>
              <.link
                :if={@location.id}
                id="cancel-location"
                phx-click="cancel_location"
                class="self-center"
              >
                {dgettext("management", "Cancel")}
              </.link>
            </div>
          </.form>
        </.panel>
      </div>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Rooms")}
        </h2>

        <ul class="mt-1 divide-y divide-secondary/10">
          <li
            :for={l <- @locations}
            id={"location-#{l.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span>
              {l.name}
              <span :if={l.private} class="badge badge-xs badge-error badge-soft ml-1">{dgettext(
                "management",
                "private"
              )}</span>
              <span
                :if={zone = Enum.find(@zones, &(&1.id == l.zone_id))}
                id={"location-zone-#{l.id}"}
                class="badge badge-xs badge-soft ml-1"
              >
                {zone.name}
              </span>

              <span
                :if={@guilds_on? && guild_name(@guilds, l.guild_id)}
                id={"location-guild-#{l.id}"}
                class="badge badge-xs badge-info badge-soft ml-1"
              >
                <.icon name="hero-flag-micro" class="size-3" /> {guild_name(@guilds, l.guild_id)}
              </span>
            </span>

            <span class="flex gap-3">
              <.link phx-click="edit_location" phx-value-id={l.id}>{dgettext("management", "Edit")}</.link>
              <.link
                phx-click="delete_location"
                phx-value-id={l.id}
                data-confirm={dgettext("management", "Delete this room and its messages?")}
              >
                {dgettext("management", "Delete")}
              </.link>
            </span>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end

  defp esiti_tab(assigns) do
    ~H"""
    <.panel>
      <.form for={@story_form} id="esiti-settings-form" phx-submit="save_story">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Esiti limits")}
        </h2>

        <p class="mb-3 text-xs text-base-content/60">
          {dgettext(
            "management",
            "Players file esiti (action requests) for the masters to resolve. Leave a field empty for no limit."
          )}
        </p>

        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input
            field={@story_form[:esiti_max_open]}
            type="number"
            label={dgettext("management", "Open requests per character")}
            min="1"
            max="50"
          />
          <.input
            field={@story_form[:esiti_min_xp]}
            type="number"
            label={dgettext("management", "Earned XP needed to file")}
            min="0"
          />
        </div>

        <.button id="save-esiti-settings" phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
          "management",
          "Save"
        )}</.button>
      </.form>
    </.panel>
    """
  end

  defp chat_tab(assigns) do
    assigns =
      assign(assigns,
        tracker_options: Enum.map(assigns.trackers, &{&1.name, &1.slug}),
        damage_types: assigns.trackers |> Enum.flat_map(& &1.damage_types) |> Enum.uniq()
      )

    ~H"""
    <.panel>
      <.form for={@story_form} id="dice-config-form" phx-submit="save_story">
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Chat history")}
        </h2>

        <.input
          field={@story_form[:archive_after_days]}
          type="number"
          label={dgettext("management", "Archive messages older than (days, empty = never)")}
          min="1"
        />
        <fieldset
          :if={Stories.module_enabled?(@current_story, :chat_rp)}
          id="chat-rp-settings"
          class="mt-4 rounded-lg border border-secondary/20 p-4"
        >
          <legend class="px-1 text-xs font-bold uppercase tracking-widest text-base-content/70">
            {dgettext("management", "Chat roleplay: entry length")}
          </legend>

          <p class="mb-2 text-xs text-base-content/60">
            {dgettext(
              "management",
              "Characters per in-character entry (speech and whispers). Leave empty for no limit."
            )}
          </p>

          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@story_form[:chat_min_length]}
              type="number"
              label={dgettext("management", "Minimum length")}
              min="0"
            />
            <.input
              field={@story_form[:chat_max_length]}
              type="number"
              label={dgettext("management", "Maximum length")}
              min="1"
              max="4000"
            />
          </div>
        </fieldset>

        <fieldset
          :if={Stories.module_enabled?(@current_story, :auto_xp)}
          id="auto-xp-settings"
          class="mt-4 rounded-lg border border-secondary/20 p-4"
        >
          <legend class="px-1 text-xs font-bold uppercase tracking-widest text-base-content/70">
            {dgettext("management", "Automatic XP")}
          </legend>

          <p class="mb-2 text-xs text-base-content/60">
            {dgettext(
              "management",
              "XP for each in-character speech of a player character (no OFF, whispers, dice or NPCs). Leave the amount empty to pause the awards."
            )}
          </p>

          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@story_form[:auto_xp_amount]}
              type="number"
              label={dgettext("management", "XP per entry")}
              min="1"
            />
            <.input
              field={@story_form[:auto_xp_min_length]}
              type="number"
              label={dgettext("management", "Minimum entry length")}
              min="0"
            />
            <.input
              field={@story_form[:auto_xp_daily_cap]}
              type="number"
              label={dgettext("management", "Daily cap per character (UTC day)")}
              min="1"
            />
            <.input
              field={@story_form[:auto_xp_cooldown_minutes]}
              type="number"
              label={dgettext("management", "Cooldown (minutes)")}
              min="0"
            />
          </div>
        </fieldset>

        <h2 class="mt-6 text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Dice system")}
        </h2>

        <.inputs_for :let={dice} field={@story_form[:dice_config]}>
          <.input
            field={dice[:system]}
            type="select"
            label={dgettext("management", "System")}
            options={[
              {dgettext("management", "Dice expression (NdX+modifier)"), "expression"},
              {dgettext("management", "d20 + modifier"), "d20"},
              {dgettext("management", "Success pool"), "pool"}
            ]}
          />
          <fieldset class="mt-4 rounded-lg border border-secondary/20 p-4">
            <legend class="px-1 text-xs font-bold uppercase tracking-widest text-base-content/70">
              {dgettext("management", "Expression and d20")}
            </legend>

            <.input
              field={dice[:default_expression]}
              type="text"
              label={dgettext("management", "Default expression")}
            />
            <.input
              field={dice[:natural_crits]}
              type="checkbox"
              label={dgettext("management", "Natural 20/1 are criticals (d20)")}
            />
          </fieldset>

          <fieldset class="mt-4 rounded-lg border border-secondary/20 p-4">
            <legend class="px-1 text-xs font-bold uppercase tracking-widest text-base-content/70">
              {dgettext("management", "Success pool")}
            </legend>

            <div class="grid gap-x-4 sm:grid-cols-3">
              <.input
                field={dice[:die_size]}
                type="number"
                label={dgettext("management", "Die size")}
                min="2"
              />
              <.input
                field={dice[:success_threshold]}
                type="number"
                label={dgettext("management", "Success on")}
                min="1"
              />
              <.input
                field={dice[:default_difficulty]}
                type="number"
                label={dgettext("management", "Default difficulty")}
              />
            </div>

            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={dice[:crit_rule]}
                type="select"
                label={dgettext("management", "Criticals")}
                options={[
                  {dgettext("management", "Each pair of max results"), "pairs"},
                  {dgettext("management", "None"), "none"}
                ]}
              />
              <.input
                field={dice[:crit_bonus]}
                type="number"
                label={dgettext("management", "Extra successes per pair")}
              />
            </div>

            <.input
              field={dice[:special_tracker]}
              type="select"
              label={dgettext("management", "Special dice count (tracker, e.g. hunger)")}
              prompt={dgettext("management", "No special dice")}
              options={@tracker_options}
            />
            <.input
              field={dice[:messy_crit]}
              type="checkbox"
              label={dgettext("management", "Messy critical: a critical with a special max result")}
            />
            <.input
              field={dice[:bestial_failure]}
              type="checkbox"
              label={dgettext("management", "Bestial failure: a failure with a special 1")}
            />
          </fieldset>

          <fieldset class="mt-4 rounded-lg border border-secondary/20 p-4">
            <legend class="px-1 text-xs font-bold uppercase tracking-widest text-base-content/70">
              {dgettext("management", "Rerolls (pool only)")}
            </legend>

            <.input
              field={dice[:reroll_tracker]}
              type="select"
              label={dgettext("management", "Spend tracker (e.g. willpower)")}
              prompt={dgettext("management", "No rerolls")}
              options={@tracker_options}
            />
            <div class="grid gap-x-4 sm:grid-cols-3">
              <.input
                field={dice[:reroll_damage_type]}
                type="select"
                label={dgettext("management", "As damage of type")}
                prompt={dgettext("management", "Lower the value")}
                options={@damage_types}
              />
              <.input
                field={dice[:reroll_cost]}
                type="number"
                label={dgettext("management", "Cost")}
                min="1"
              />
              <.input
                field={dice[:reroll_max_dice]}
                type="number"
                label={dgettext("management", "Max dice")}
                min="0"
              />
            </div>
          </fieldset>
        </.inputs_for>

        <.button phx-disable-with={dgettext("management", "Saving...")} class="mt-4">{dgettext(
          "management",
          "Save chat & dice"
        )}</.button>
      </.form>
    </.panel>
    """
  end

  defp forum_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @section.id,
            do: dgettext("management", "Edit section"),
            else: dgettext("management", "New section")}
        </h2>

        <p class="mt-1 text-sm text-base-content/60">
          {dgettext(
            "management",
            "On-game sections are written in character (only characters that can play); off-game ones as the player. Visibility limits who can read and write."
          )}
        </p>

        <.form for={@section_form} id="section-form" phx-submit="save_section">
          <.input
            field={@section_form[:name]}
            type="text"
            label={dgettext("management", "Name")}
            required
          />
          <.input
            field={@section_form[:description]}
            type="text"
            label={dgettext("management", "Description")}
          />
          <.input
            field={@section_form[:position]}
            type="number"
            label={dgettext("management", "Position")}
          />
          <.input
            field={@section_form[:on_game]}
            type="checkbox"
            label={dgettext("management", "On game (in character)")}
          />
          <.input
            field={@section_form[:visibility]}
            type="select"
            label={dgettext("management", "Visible to")}
            options={section_visibilities(@guilds_on?, @section)}
          />
          <.input
            :if={@guilds_on?}
            field={@section_form[:guild_id]}
            type="select"
            label={dgettext("management", "Guild (for guild sections)")}
            prompt={dgettext("management", "Choose a guild")}
            options={Enum.map(@guilds, &{&1.name, &1.id})}
          />
          <div class="flex gap-3">
            <.button phx-disable-with={dgettext("management", "Saving...")}>
              {if @section.id,
                do: dgettext("management", "Save section"),
                else: dgettext("management", "Create section")}
            </.button>

            <.link
              :if={@section.id}
              id="cancel-section"
              phx-click="cancel_section"
              class="self-center"
            >
              {dgettext("management", "Cancel")}
            </.link>
          </div>
        </.form>
      </.panel>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Sections")}
        </h2>

        <ul class="mt-1 divide-y divide-secondary/10">
          <li
            :for={{s, count} <- @sections}
            id={"section-#{s.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span class="flex flex-wrap items-center gap-1.5">
              {s.name}
              <span class={[
                "badge badge-xs",
                if(s.on_game, do: "badge-primary badge-soft", else: "badge-ghost")
              ]}>
                {if s.on_game,
                  do: dgettext("management", "On game"),
                  else: dgettext("management", "Off game")}
              </span>

              <span :if={s.visibility != "all"} class="badge badge-xs badge-warning badge-soft">
                {Forum.visibility_label(s.visibility)}
              </span>

              <span
                :if={s.visibility == "guild" && guild_name(@guilds, s.guild_id)}
                id={"section-guild-#{s.id}"}
                class="badge badge-xs badge-info badge-soft"
              >
                <.icon name="hero-flag-micro" class="size-3" /> {guild_name(@guilds, s.guild_id)}
              </span>

              <span class="text-base-content/50">{dgettext("management", "%{count} topics",
                count: count
              )}</span>
            </span>

            <span class="flex shrink-0 gap-3">
              <.link id={"edit-section-#{s.id}"} phx-click="edit_section" phx-value-id={s.id}>
                {dgettext("management", "Edit")}
              </.link>

              <.link
                id={"delete-section-#{s.id}"}
                phx-click="delete_section"
                phx-value-id={s.id}
                data-confirm={dgettext("management", "Delete this section and all its topics?")}
              >
                {dgettext("management", "Delete")}
              </.link>
            </span>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end

  defp masters_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Add a master")}
        </h2>

        <p class="mt-1 text-sm text-base-content/60">
          {dgettext(
            "management",
            "Masters narrate the GDR: they run chats, edit characters and moderate the forum, but cannot change this configuration. Their permissions can be narrowed below."
          )}
        </p>

        <.form for={@master_form} id="master-form" phx-submit="add_master">
          <.input
            field={@master_form[:username]}
            type="text"
            label={dgettext("management", "Username")}
            autocomplete="off"
            required
          />
          <.button phx-disable-with={dgettext("management", "Adding...")}>{dgettext(
            "management",
            "Add master"
          )}</.button>
        </.form>
      </.panel>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {dgettext("management", "Masters")}
        </h2>

        <p :if={@masters_empty?} id="no-masters" class="mt-2 text-sm text-base-content/60">
          {dgettext("management", "No masters yet.")}
        </p>

        <p class="mt-1 text-xs text-base-content/60">
          {dgettext(
            "management",
            "Tick what each master may do. The GDR admin and platform admins can always do everything."
          )}
        </p>

        <ul id="masters" phx-update="stream" class="mt-1 divide-y divide-secondary/10">
          <li
            :for={{dom_id, master} <- @streams.masters}
            id={dom_id}
            class="py-3 text-sm"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="font-semibold">{master.user.username}</span>
              <.link
                id={"remove-master-#{master.user_id}"}
                phx-click="remove_master"
                phx-value-id={master.user_id}
                data-confirm={
                  dgettext("management", "Remove %{master_user_username} from the masters?",
                    master_user_username: master.user.username
                  )
                }
              >
                {dgettext("management", "Remove")}
              </.link>
            </div>

            <div
              id={"master-permissions-#{master.user_id}"}
              class="mt-2 grid gap-x-4 gap-y-1 sm:grid-cols-2"
            >
              <label
                :for={{key, label, description} <- Stories.permissions()}
                class="flex cursor-pointer items-center gap-2 text-xs text-base-content/80 transition-colors hover:text-base-content"
                title={description}
              >
                <input
                  type="checkbox"
                  id={"master-#{master.user_id}-#{key}"}
                  class="checkbox checkbox-xs console-check"
                  checked={Map.fetch!(master, key)}
                  phx-click="toggle_permission"
                  phx-value-user_id={master.user_id}
                  phx-value-perm={key}
                  phx-value-value={to_string(!Map.fetch!(master, key))}
                /> {label}
              </label>
            </div>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end
end
