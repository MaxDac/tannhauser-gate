defmodule TannhauserGateWeb.GmLive do
  @moduledoc """
  Dashboard where the game master (or an admin) edits the GDR: general info,
  theme, character sheet, jobs, balances, map and forum sections.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Bank, Characters, Forum, Sheet, Stories}
  alias TannhauserGate.Bank.Job
  alias TannhauserGate.Forum.Section
  alias TannhauserGate.Sheet.Item
  alias TannhauserGate.Stories.{Location, Themes}

  @tabs [
    {"general", "General"},
    {"theme", "Theme"},
    {"sheet", "Sheet"},
    {"jobs", "Jobs"},
    {"balances", "Balances"},
    {"map", "Map"},
    {"forum", "Forum"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :tabs, @tabs)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = params["tab"] || "general"

    if tab in Enum.map(@tabs, &elem(&1, 0)) do
      {:noreply, socket |> assign(:tab, tab) |> assign(:page_title, "GM dashboard") |> load(tab)}
    else
      {:noreply, push_patch(socket, to: ~p"/g/#{socket.assigns.current_story}/gm")}
    end
  end

  defp story(socket), do: socket.assigns.current_story

  defp load(socket, "general"), do: assign_story_form(socket, story(socket))
  defp load(socket, "theme"), do: assign_story_form(socket, story(socket))
  defp load(socket, "map"), do: socket |> assign_story_form(story(socket)) |> reload_locations()

  defp load(socket, "sheet") do
    socket
    |> assign(:items, Sheet.list_items(story(socket)))
    |> assign_item_form(%Item{})
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
    |> assign(:sections, Forum.list_sections(story(socket)))
    |> assign(:section_form, to_form(Forum.change_section(%Section{}), as: :section))
  end

  defp assign_story_form(socket, story) do
    socket
    |> assign(:story_form, to_form(Stories.change_story_as_gm(story), as: :story))
    |> assign(:preset_names, Themes.presets())
    |> assign(:color_keys, Themes.color_keys())
  end

  defp assign_item_form(socket, item),
    do:
      socket
      |> assign(:item, item)
      |> assign(:item_form, to_form(Sheet.change_item(item), as: :item))

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
    |> assign_location_form(%Location{})
  end

  ## Story (general / theme / map)

  @impl true
  def handle_event("save_story", %{"story" => params}, socket) do
    case Stories.update_story_as_gm(story(socket), params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:current_story, updated)
         |> put_flash(:info, "GDR updated")
         |> assign_story_form(updated)}

      {:error, changeset} ->
        {:noreply, assign(socket, :story_form, to_form(changeset, as: :story))}
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
        {:noreply, socket |> put_flash(:info, "Saved") |> load("sheet")}

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

  ## Jobs

  def handle_event("save_job", %{"job" => params}, socket) do
    job = socket.assigns.job

    result =
      if job.id, do: Bank.update_job(job, params), else: Bank.create_job(story(socket), params)

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Saved") |> load("jobs")}

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
          {:noreply, socket |> put_flash(:info, "Balance updated") |> load("balances")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, Bank.error_message(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "That character is not in this GDR.")}
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
        {:noreply, socket |> put_flash(:info, "Saved") |> reload_locations()}

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

  def handle_event("create_section", %{"section" => params}, socket) do
    case Forum.create_section(story(socket), params) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Section created") |> load("forum")}

      {:error, changeset} ->
        {:noreply, assign(socket, :section_form, to_form(changeset, as: :section))}
    end
  end

  def handle_event("delete_section", %{"id" => id}, socket) do
    section = Forum.get_section!(id)

    if section.story_id == story(socket).id do
      {:ok, _} = Forum.delete_section(section)
      {:noreply, load(socket, "forum")}
    else
      {:noreply, put_flash(socket, :error, "That section is not in this GDR.")}
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
    >
      <.header>
        GM dashboard
        <:subtitle>Shape {@current_story.name}: rules, look, sheet, economy and map.</:subtitle>
      </.header>

      <nav
        id="gm-tabs"
        class="mt-6 flex flex-wrap gap-2 border-b border-secondary/20 pb-3"
        aria-label="Dashboard"
      >
        <.link
          :for={{key, label} <- @tabs}
          id={"gm-tab-#{key}"}
          patch={~p"/g/#{@current_story}/gm/#{key}"}
          class={[
            "rounded-md px-3 py-1.5 text-xs font-bold uppercase tracking-wider",
            if(@tab == key,
              do: "bg-primary/20 text-primary",
              else: "text-base-content/60 hover:text-secondary"
            )
          ]}
        >
          {label}
        </.link>
      </nav>

      <div class="mt-6">
        <.general_tab :if={@tab == "general"} {assigns} />
        <.theme_tab :if={@tab == "theme"} {assigns} /> <.sheet_tab :if={@tab == "sheet"} {assigns} />
        <.jobs_tab :if={@tab == "jobs"} {assigns} />
        <.balances_tab :if={@tab == "balances"} {assigns} />
        <.map_tab :if={@tab == "map"} {assigns} /> <.forum_tab :if={@tab == "forum"} {assigns} />
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
      <.form for={@story_form} id="general-form" phx-submit="save_story">
        <.input field={@story_form[:name]} type="text" label="Name" required />
        <.input field={@story_form[:summary]} type="textarea" label="Summary" rows="3" />
        <.input
          field={@story_form[:world_background]}
          type="textarea"
          label="Background / story"
          rows="8"
        /> <.input field={@story_form[:rules]} type="textarea" label="Rules" rows="8" />
        <.input field={@story_form[:customs]} type="textarea" label="Customs" rows="4" />
        <.input field={@story_form[:currency_name]} type="text" label="Currency name" />
        <.input
          field={@story_form[:pay_interval_hours]}
          type="number"
          label="Pay interval (hours)"
          min="1"
        />
        <.input
          field={@story_form[:status]}
          type="select"
          label="Status"
          options={[{"Draft (only you)", "draft"}, {"Published", "published"}]}
        /> <.button phx-disable-with="Saving...">Save</.button>
      </.form>
    </.panel>
    """
  end

  defp theme_tab(assigns) do
    ~H"""
    <.panel>
      <.form for={@story_form} id="theme-form" phx-submit="save_story">
        <.input
          field={@story_form[:theme]}
          type="select"
          label="Preset"
          options={@preset_names}
        />
        <h2 class="mt-4 text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          Custom colors (hex, e.g. #22cc88 — leave empty to keep the preset)
        </h2>

        <div class="mt-2 grid gap-x-6 sm:grid-cols-2">
          <.input
            :for={key <- @color_keys}
            type="text"
            id={"override-#{key}"}
            name={"story[theme_overrides][#{key}]"}
            value={(@story_form[:theme_overrides].value || %{})[key]}
            label={key}
            placeholder="#rrggbb"
          />
        </div>

        <.error :for={msg <- Enum.map(@story_form[:theme_overrides].errors, &translate_error/1)}>
          {msg}
        </.error>
        <.button phx-disable-with="Saving...">Save theme</.button>
      </.form>
    </.panel>
    """
  end

  defp sheet_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @item.id, do: "Edit item", else: "New item"}
        </h2>

        <.form for={@item_form} id="item-form" phx-submit="save_item">
          <.input
            field={@item_form[:kind]}
            type="select"
            label="Kind"
            options={Enum.map(Sheet.kinds(), &{String.capitalize(&1), &1})}
          /> <.input field={@item_form[:name]} type="text" label="Name" required />
          <.input field={@item_form[:description]} type="textarea" label="Description" rows="2" />
          <div class="grid grid-cols-3 gap-3">
            <.input field={@item_form[:min_value]} type="number" label="Min" />
            <.input field={@item_form[:max_value]} type="number" label="Max" />
            <.input field={@item_form[:position]} type="number" label="Order" />
          </div>

          <div class="flex gap-3">
            <.button phx-disable-with="Saving...">Save item</.button>
            <.link :if={@item.id} id="cancel-item" phx-click="cancel_item" class="self-center">
              Cancel
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
              <span>{i.name} <span class="text-base-content/50">{i.min_value}–{i.max_value}</span></span>
              <span class="flex gap-3">
                <.link phx-click="edit_item" phx-value-id={i.id}>Edit</.link>
                <.link
                  phx-click="delete_item"
                  phx-value-id={i.id}
                  data-confirm="Delete this item? Character values for it are removed."
                >
                  Delete
                </.link>
              </span>
            </li>
          </ul>
        </div>
      </.panel>
    </div>
    """
  end

  defp jobs_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
          {if @job.id, do: "Edit job", else: "New job"}
        </h2>

        <.form for={@job_form} id="job-form" phx-submit="save_job">
          <.input field={@job_form[:name]} type="text" label="Name" required />
          <.input field={@job_form[:description]} type="textarea" label="Description" rows="2" />
          <.input
            field={@job_form[:pay]}
            type="number"
            label={"Pay (#{@current_story.currency_name} per interval)"}
            min="0"
          />
          <div class="flex gap-3">
            <.button phx-disable-with="Saving...">Save job</.button>
            <.link :if={@job.id} id="cancel-job" phx-click="cancel_job" class="self-center">
              Cancel
            </.link>
          </div>
        </.form>
      </.panel>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Jobs</h2>

        <p :if={@jobs == []} class="mt-2 text-sm text-base-content/60">No jobs yet.</p>

        <ul class="mt-1 divide-y divide-secondary/10">
          <li
            :for={j <- @jobs}
            id={"job-row-#{j.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span>{j.name} <span class="text-base-content/50">{j.pay}</span></span>
            <span class="flex gap-3">
              <.link phx-click="edit_job" phx-value-id={j.id}>Edit</.link>
              <.link
                phx-click="delete_job"
                phx-value-id={j.id}
                data-confirm="Delete this job? Characters holding it become unemployed."
              >
                Delete
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
      <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Balances</h2>

      <p :if={@characters == []} class="mt-2 text-sm text-base-content/60">No characters yet.</p>

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
            placeholder="+/- amount"
            class="input input-sm console-field w-32"
            aria-label={"Amount for #{c.name}"}
          />
          <input
            type="text"
            name="adjust[note]"
            placeholder="Note"
            class="input input-sm console-field w-48"
            aria-label={"Note for #{c.name}"}
          /> <.button class="btn btn-sm">Apply</.button>
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
            <.input field={@story_form[:map_svg]} type="textarea" label="Map SVG" rows="6" />
            <div class="grid grid-cols-2 gap-3">
              <.input field={@story_form[:map_width]} type="number" label="Width" />
              <.input field={@story_form[:map_height]} type="number" label="Height" />
            </div>
            <.button phx-disable-with="Saving...">Save map</.button>
          </.form>
        </.panel>

        <.panel>
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
            {if @location.id, do: "Edit room", else: "New room"}
          </h2>

          <.form for={@location_form} id="location-form" phx-submit="save_location">
            <.input field={@location_form[:name]} type="text" label="Name" required />
            <.input field={@location_form[:description]} type="textarea" label="Description" rows="2" />
            <.input field={@location_form[:area]} type="text" label="Map area (SVG path)" />
            <.input field={@location_form[:color]} type="text" label="Color" />
            <div class="flex gap-3">
              <.button phx-disable-with="Saving...">Save room</.button>
              <.link
                :if={@location.id}
                id="cancel-location"
                phx-click="cancel_location"
                class="self-center"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </.panel>
      </div>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Rooms</h2>

        <ul class="mt-1 divide-y divide-secondary/10">
          <li
            :for={l <- @locations}
            id={"location-#{l.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span>{l.name}</span>
            <span class="flex gap-3">
              <.link phx-click="edit_location" phx-value-id={l.id}>Edit</.link>
              <.link
                phx-click="delete_location"
                phx-value-id={l.id}
                data-confirm="Delete this room and its messages?"
              >
                Delete
              </.link>
            </span>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end

  defp forum_tab(assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-2">
      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">New section</h2>

        <.form for={@section_form} id="section-form" phx-submit="create_section">
          <.input field={@section_form[:name]} type="text" label="Name" required />
          <.input field={@section_form[:description]} type="text" label="Description" />
          <.input field={@section_form[:position]} type="number" label="Position" />
          <.button phx-disable-with="Saving...">Create section</.button>
        </.form>
      </.panel>

      <.panel>
        <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Sections</h2>

        <ul class="mt-1 divide-y divide-secondary/10">
          <li
            :for={{s, count} <- @sections}
            id={"section-#{s.id}"}
            class="flex items-center justify-between gap-2 py-1.5 text-sm"
          >
            <span>{s.name} <span class="text-base-content/50">{count} topics</span></span>
            <.link
              phx-click="delete_section"
              phx-value-id={s.id}
              data-confirm="Delete this section and all its topics?"
            >
              Delete
            </.link>
          </li>
        </ul>
      </.panel>
    </div>
    """
  end
end
