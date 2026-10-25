defmodule TannhauserGateWeb.Admin.Components do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: TannhauserGateWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: TannhauserGateWeb.Endpoint,
    router: TannhauserGateWeb.Router,
    statics: TannhauserGateWeb.static_paths()

  defp links,
    do: [
      {dgettext("management", "Dashboard"), "/admin"},
      {dgettext("management", "Stories"), "/admin/stories"},
      {dgettext("management", "Characters"), "/admin/characters"},
      {dgettext("management", "Rooms"), "/admin/rooms"},
      {dgettext("management", "Users"), "/admin/users"},
      {dgettext("management", "Requests"), "/admin/requests"},
      {dgettext("management", "Reviews"), "/admin/reviews"},
      {dgettext("management", "Forum"), "/admin/forum"}
    ]

  attr :current_path, :string, default: nil

  def admin_nav(assigns) do
    assigns = assign(assigns, :links, links())

    ~H"""
    <nav
      id="admin-nav"
      class="mb-8 flex flex-wrap gap-2 border-b border-mint/20 pb-4"
      aria-label={dgettext("management", "Admin")}
    >
      <.link
        :for={{label, path} <- @links}
        navigate={path}
        class={[
          "rounded-md px-3 py-1.5 text-xs font-bold uppercase tracking-wider",
          active?(@current_path, path) && "bg-phosphor/20 text-phosphor",
          !active?(@current_path, path) && "text-fog-300 hover:bg-mint/10 hover:text-mint"
        ]}
      >
        {label}
      </.link>
    </nav>
    """
  end

  defp active?(nil, _), do: false
  defp active?(current, "/admin"), do: current == "/admin"
  defp active?(current, path), do: String.starts_with?(current, path)
end

defmodule TannhauserGateWeb.Admin.DashboardLive do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.{Accounts, Characters, Forum, Repo, Stories}
  alias TannhauserGate.Chat.Message

  @impl true
  def mount(_params, _session, socket) do
    stats = [
      {dgettext("management", "Stories"), length(Stories.list_stories()), ~p"/admin/stories"},
      {dgettext("management", "Rooms"), length(Stories.list_all_locations()), ~p"/admin/rooms"},
      {dgettext("management", "Characters"), length(Characters.list_characters()),
       ~p"/admin/characters"},
      {dgettext("management", "Messages"), Repo.aggregate(Message, :count), ~p"/admin/rooms"},
      {dgettext("management", "Users"), length(Accounts.list_users()), ~p"/admin/users"},
      {dgettext("management", "Forum sections"), length(Forum.list_sections()), ~p"/admin/forum"}
    ]

    {:ok, assign(socket, page_title: dgettext("management", "Admin"), stats: stats)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>
        {dgettext("management", "Control room")}
        <:subtitle>
          {dgettext(
            "management",
            "Run the city: stories, maps, characters, conversations and people."
          )}
        </:subtitle>
      </.header>

      <div id="admin-stats" class="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={{label, count, path} <- @stats}
          navigate={path}
          class="rounded-xl border border-mint/20 bg-ink/80 p-5 hover:border-phosphor/60 hover:shadow-phosphor"
        >
          <p class="text-xs uppercase tracking-[0.2em] text-mint">{label}</p>

          <p class="mt-2 text-4xl font-bold text-phosphor">{count}</p>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end

defmodule TannhauserGateWeb.Admin.StoryLive.Index do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.Stories

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: dgettext("management", "Stories"),
       stories: Stories.list_stories()
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Stories.get_story!() |> Stories.delete_story()

    {:noreply,
     socket
     |> put_flash(:info, dgettext("management", "Story deleted"))
     |> assign(:stories, Stories.list_stories())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>
        {dgettext("management", "Stories")}
        <:actions>
          <.button navigate={~p"/admin/stories/new"}>{dgettext("management", "New story")}</.button>
        </:actions>
      </.header>

      <.table id="stories" rows={@stories}>
        <:col :let={story} label={dgettext("management", "Name")}>
          {story.name}
          <span
            :if={story.is_default}
            class="badge badge-primary badge-soft badge-sm ml-2"
          >{dgettext("management", "default")}</span>
        </:col>

        <:col :let={story} label={dgettext("management", "Summary")}>
          <span class="line-clamp-2">{story.summary}</span>
        </:col>

        <:action :let={story}>
          <.link navigate={~p"/g/#{story}"}>{dgettext("management", "Open")}</.link>
        </:action>

        <:action :let={story}>
          <.link navigate={~p"/admin/stories/#{story}/edit"}>{dgettext("management", "Edit")}</.link>
        </:action>

        <:action :let={story}>
          <.link
            phx-click="delete"
            phx-value-id={story.id}
            data-confirm={
              dgettext("management", "Delete this story with all its rooms, characters and messages?")
            }
          >
            {dgettext("management", "Delete")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end

defmodule TannhauserGateWeb.Admin.StoryLive.Form do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.{Directory, Stories}
  alias TannhauserGate.Stories.{Location, Story}

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    story = %Story{locations: []}

    socket
    |> assign(:page_title, dgettext("management", "New story"))
    |> assign(:story, story)
    |> assign(:form, to_form(Stories.change_story(story)))
    |> assign_location_form(%Location{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    story = Stories.get_story!(id)

    socket
    |> assign(:page_title, dgettext("management", "Edit %{story_name}", story_name: story.name))
    |> assign(:story, story)
    |> assign(:form, to_form(Stories.change_story(story)))
    |> assign_location_form(%Location{})
  end

  defp assign_location_form(socket, location, changeset \\ nil) do
    changeset = changeset || Stories.change_location(location)

    socket
    |> assign(:location, location)
    |> assign(:location_form, to_form(changeset))
  end

  @impl true
  def handle_event("validate", %{"story" => params}, socket) do
    changeset = Stories.change_story(socket.assigns.story, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"story" => params}, socket) do
    result =
      if socket.assigns.story.id,
        do: Stories.update_story(socket.assigns.story, params),
        else: Stories.create_story(params)

    case result do
      {:ok, story} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("management", "Story saved"))
         |> push_navigate(to: ~p"/admin/stories/#{story}/edit")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit_location", %{"id" => id}, socket) do
    {:noreply, assign_location_form(socket, Stories.get_location!(id))}
  end

  def handle_event("new_location", _params, socket) do
    {:noreply, assign_location_form(socket, %Location{})}
  end

  def handle_event("save_location", %{"location" => params}, socket) do
    story = socket.assigns.story

    result =
      case socket.assigns.location do
        %Location{id: nil} -> Stories.create_location(story, params)
        location -> Stories.update_location(location, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("management", "Room saved"))
         |> assign(:story, Stories.get_story!(story.id))
         |> assign_location_form(%Location{})}

      {:error, changeset} ->
        {:noreply, assign_location_form(socket, socket.assigns.location, changeset)}
    end
  end

  def handle_event("delete_location", %{"id" => id}, socket) do
    {:ok, _} = id |> Stories.get_location!() |> Stories.delete_location()

    {:noreply,
     socket
     |> put_flash(:info, dgettext("management", "Room deleted"))
     |> assign(:story, Stories.get_story!(socket.assigns.story.id))
     |> assign_location_form(%Location{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>
        {@page_title}
        <:subtitle>
          {dgettext(
            "management",
            "The story and the map of its world. Its masters write the world guide."
          )}
        </:subtitle>
      </.header>

      <div class="mt-6 rounded-xl border border-mint/20 bg-ink/80 p-6">
        <.form for={@form} id="story-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label={dgettext("management", "Name")} required />
          <.input
            field={@form[:summary]}
            type="textarea"
            label={dgettext("management", "Summary")}
            rows="2"
          />
          <fieldset id="story-listing" class="mt-2 min-w-0 border-t border-mint/20 pt-4">
            <legend class="text-sm font-semibold text-fog-300">
              {dgettext("management", "Directory listing")}
            </legend>

            <.input
              field={@form[:pitch]}
              type="text"
              label={dgettext("management", "Pitch")}
              maxlength="160"
            /> <input type="hidden" name="story[genres][]" value="" />
            <.input
              field={@form[:genres]}
              type="select"
              label={dgettext("management", "Genres (up to 3)")}
              multiple
              size="6"
              class="block h-auto w-full console-field py-1"
              options={for {value, label} <- Directory.genres(), do: {label, value}}
            />
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={@form[:lifecycle]}
                type="select"
                label={dgettext("management", "Lifecycle")}
                options={for {value, label} <- Directory.lifecycles(), do: {label, value}}
              />
              <.input
                field={@form[:content_rating]}
                type="select"
                label={dgettext("management", "Content rating")}
                options={for {value, label} <- Directory.content_ratings(), do: {label, value}}
              />
            </div>
          </fieldset>

          <div class="grid gap-4 sm:grid-cols-3">
            <.input
              field={@form[:map_width]}
              type="number"
              label={dgettext("management", "Map width")}
            />
            <.input
              field={@form[:map_height]}
              type="number"
              label={dgettext("management", "Map height")}
            />
            <.input
              field={@form[:is_default]}
              type="checkbox"
              label={dgettext("management", "Default story")}
            />
          </div>

          <.input
            field={@form[:map_svg]}
            type="textarea"
            label={dgettext("management", "Map artwork (inner SVG markup, no scripts)")}
            rows="8"
            class="w-full textarea console-field font-mono text-xs"
          />
          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
              "management",
              "Save story"
            )}</.button>
          </div>
        </.form>
      </div>

      <section :if={@story.id} id="story-rooms" class="mt-10">
        <h2 class="text-lg font-bold uppercase tracking-[0.2em] text-mint">
          {dgettext("management", "Rooms on the map")}
        </h2>

        <p class="text-sm text-fog-400">
          {dgettext("management", "Areas are SVG polygon points in map coordinates, e.g.")} <code>100,100 200,100 200,200 100,200</code>.
        </p>

        <div class="mt-4 grid gap-6 lg:grid-cols-2">
          <div class="overflow-hidden rounded-xl border border-mint/30 bg-night">
            <svg viewBox={"0 0 #{@story.map_width} #{@story.map_height}"} class="block h-auto w-full">
              <image
                :if={@story.map_svg not in [nil, ""]}
                href={Stories.map_artwork_src(@story)}
                width={@story.map_width}
                height={@story.map_height}
              />
              <polygon
                :for={loc <- @story.locations}
                points={loc.area}
                fill={loc.color}
                stroke={loc.color}
                class="map-room-static"
              />
            </svg>
          </div>

          <div class="rounded-xl border border-mint/20 bg-ink/80 p-6">
            <h3 class="text-sm font-bold uppercase tracking-wider text-phosphor">
              {if @location.id,
                do: dgettext("management", "Edit room"),
                else: dgettext("management", "New room")}
            </h3>

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
                rows="3"
              />
              <.input
                field={@location_form[:area]}
                type="text"
                label={dgettext("management", "Area (polygon points)")}
                required
              />
              <.input
                field={@location_form[:color]}
                type="text"
                label={dgettext("management", "Color")}
              />
              <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
                <.button phx-disable-with={dgettext("management", "Saving...")}>{dgettext(
                  "management",
                  "Save room"
                )}</.button>
                <button
                  :if={@location.id}
                  type="button"
                  phx-click="new_location"
                  class="console-link-action text-sm text-fog-400 hover:text-mint"
                >
                  {dgettext("management", "Cancel")}
                </button>
              </div>
            </.form>
          </div>
        </div>

        <.table id="locations" rows={@story.locations}>
          <:col :let={loc} label={dgettext("management", "Room")}>
            <span
              class="mr-2 inline-block h-2.5 w-2.5 rounded-full"
              style={"background: #{loc.color}"}
            ></span>{loc.name}
          </:col>

          <:col :let={loc} label={dgettext("management", "Area")}>
            <code class="text-xs">{loc.area}</code>
          </:col>

          <:action :let={loc}>
            <.link phx-click="edit_location" phx-value-id={loc.id}>{dgettext("management", "Edit")}</.link>
          </:action>

          <:action :let={loc}>
            <.link navigate={~p"/admin/rooms/#{loc}"}>{dgettext("management", "Conversation")}</.link>
          </:action>

          <:action :let={loc}>
            <.link
              phx-click="delete_location"
              phx-value-id={loc.id}
              data-confirm={dgettext("management", "Delete this room and its messages?")}
            >
              {dgettext("management", "Delete")}
            </.link>
          </:action>
        </.table>
      </section>
    </Layouts.app>
    """
  end
end

defmodule TannhauserGateWeb.Admin.CharactersLive do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.Characters

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: dgettext("management", "All characters"),
       characters: Characters.list_characters()
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Characters.get_character!() |> Characters.delete_character()

    {:noreply,
     socket
     |> put_flash(:info, dgettext("management", "Character deleted"))
     |> assign(:characters, Characters.list_characters())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>{dgettext("management", "All characters")}</.header>

      <.table id="admin-characters" rows={@characters}>
        <:col :let={c} label={dgettext("management", "Character")}>
          <span class="flex items-center gap-3">
            <.avatar character={c} class="h-8 w-8" />{c.name}
          </span>
        </:col>

        <:col :let={c} label={dgettext("management", "Story")}>{c.story.name}</:col>

        <:col :let={c} label={dgettext("management", "Player")}>{c.user.username}</:col>

        <:action :let={c}>
          <.link navigate={~p"/g/#{c.story_id}/characters/#{c}"}>{dgettext("management", "View")}</.link>
        </:action>

        <:action :let={c}>
          <.link navigate={~p"/g/#{c.story_id}/characters/#{c}/edit"}>{dgettext("management", "Edit")}</.link>
        </:action>

        <:action :let={c}>
          <.link
            phx-click="delete"
            phx-value-id={c.id}
            data-confirm={dgettext("management", "Delete this character?")}
          >{dgettext("management", "Delete")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end

defmodule TannhauserGateWeb.Admin.RoomsLive do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.{Chat, Stories}

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    location = Stories.get_location!(id)

    if connected?(socket) do
      Chat.subscribe(location.id)
      Chat.subscribe_whispers(location.id, :all)
    end

    {:noreply,
     socket
     |> assign(
       :page_title,
       dgettext("management", "Conversation · %{location_name}", location_name: location.name)
     )
     |> assign(:location, location)
     |> stream(:messages, Chat.list_messages(location.id, limit: 500, viewer: :all), reset: true)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:page_title, dgettext("management", "Rooms"))
     |> assign(:locations, Stories.list_all_locations())
     |> assign(:counts, Chat.count_messages_by_location())}
  end

  @impl true
  def handle_event("delete_message", %{"id" => id}, socket) do
    {:ok, _} = id |> Chat.get_message!() |> Chat.delete_message()
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, message}, socket),
    do: {:noreply, stream_insert(socket, :messages, message)}

  def handle_info({:deleted_message, message}, socket),
    do: {:noreply, stream_delete(socket, :messages, message)}

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>
        {@location.name}
        <:subtitle>
          {dgettext("management", "%{location_story_name} · conversation log",
            location_story_name: @location.story.name
          )}
        </:subtitle>

        <:actions>
          <.link navigate={~p"/admin/rooms"} class="text-sm font-semibold text-mint">{dgettext(
            "management",
            "All rooms"
          )}</.link>
        </:actions>
      </.header>

      <ol id="admin-messages" phx-update="stream" class="mt-6 space-y-3">
        <li class="hidden only:block text-sm text-fog-500" id="admin-messages-empty">
          {dgettext("management", "No messages.")}
        </li>

        <li
          :for={{dom_id, m} <- @streams.messages}
          id={dom_id}
          class="flex gap-3 rounded-lg border border-mint/20 bg-ink/80 p-3"
        >
          <.avatar :if={m.character} character={m.character} class="h-9 w-9 shrink-0" />
          <span
            :if={!m.character}
            class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-warning/10 text-warning ring-2 ring-warning/40"
          >
            <.icon name="hero-book-open" class="size-4" />
          </span>

          <div class="min-w-0 flex-1">
            <p class="text-xs text-fog-500">
              <span class="font-bold text-phosphor">{TannhauserGate.Chat.speaker_name(m)}</span>
              ({m.user.username}) · {format_time(m.inserted_at)}
            </p>

            <p class="whitespace-pre-line break-words">{m.body}</p>
          </div>

          <button
            type="button"
            phx-click="delete_message"
            phx-value-id={m.id}
            data-confirm={dgettext("management", "Delete this message?")}
            class="console-link-action self-start text-xs text-red-400 hover:underline"
          >
            {dgettext("management", "Delete")}
          </button>
        </li>
      </ol>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>{dgettext("management", "Rooms & conversations")}</.header>

      <.table id="admin-rooms" rows={@locations} row_click={&JS.navigate(~p"/admin/rooms/#{&1}")}>
        <:col :let={l} label={dgettext("management", "Room")}>{l.name}</:col>

        <:col :let={l} label={dgettext("management", "Story")}>{l.story.name}</:col>

        <:col :let={l} label={dgettext("management", "Messages")}>{Map.get(@counts, l.id, 0)}</:col>

        <:action :let={l}>
          <.link navigate={~p"/admin/rooms/#{l}"}>{dgettext("management", "Read")}</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end

defmodule TannhauserGateWeb.Admin.UsersLive do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, page_title: dgettext("management", "Users"), users: Accounts.list_users())}
  end

  @impl true
  def handle_event("toggle", %{"id" => id, "flag" => flag}, socket) when flag in ~w(admin gm) do
    user = Accounts.get_user!(id)

    if flag == "admin" and user.id == socket.assigns.current_user.id do
      {:noreply,
       put_flash(socket, :error, dgettext("management", "You can't change your own admin flag."))}
    else
      attrs = %{String.to_existing_atom(flag) => !Map.fetch!(user, String.to_existing_atom(flag))}

      case Accounts.set_user_flags(user, attrs) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("management", "Role updated"))
           |> assign(:users, Accounts.list_users())}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("management", "Invalid role"))}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>{dgettext("management", "Users")}</.header>

      <.table id="admin-users" rows={@users}>
        <:col :let={u} label={dgettext("management", "Username")}>{u.username}</:col>

        <:col :let={u} label={dgettext("management", "Email")}>{u.email}</:col>

        <:col :let={u} label={dgettext("management", "Role")}>
          <span class={[u.admin && "text-phosphor font-bold"]}>{if u.admin,
            do: dgettext("management", "admin"),
            else: dgettext("management", "user")}</span>
          <span :if={u.gm} class="badge badge-secondary badge-soft badge-sm ml-2">{dgettext(
            "management",
            "GM"
          )}</span>
        </:col>

        <:col :let={u} label={dgettext("management", "Joined")}>{format_time(u.inserted_at)}</:col>

        <:action :let={u}>
          <.link
            :if={u.id != @current_user.id}
            id={"toggle-admin-#{u.id}"}
            phx-click="toggle"
            phx-value-id={u.id}
            phx-value-flag="admin"
          >
            {if u.admin,
              do: dgettext("management", "Revoke admin"),
              else: dgettext("management", "Make admin")}
          </.link>
        </:action>

        <:action :let={u}>
          <.link
            id={"toggle-gm-#{u.id}"}
            phx-click="toggle"
            phx-value-id={u.id}
            phx-value-flag="gm"
          >
            {if u.gm, do: dgettext("management", "Revoke GM"), else: dgettext("management", "Make GM")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end

defmodule TannhauserGateWeb.Admin.ForumLive do
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.Admin.Components

  alias TannhauserGate.Forum

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, dgettext("management", "Forum sections"))
     |> assign(:sections, Forum.list_sections())}
  end

  @impl true
  def handle_event("delete_section", %{"id" => id}, socket) do
    {:ok, _} = id |> Forum.get_section!() |> Forum.delete_section()

    {:noreply,
     socket
     |> put_flash(:info, dgettext("management", "Section deleted"))
     |> assign(:sections, Forum.list_sections())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_path={@current_path}>
      <.admin_nav current_path={@current_path} />
      <.header>
        {dgettext("management", "Forum sections")}
        <:subtitle>
          {dgettext("management", "Sections are created by each GDR's game master.")}
        </:subtitle>
      </.header>

      <.table id="admin-sections" rows={@sections}>
        <:col :let={{s, _}} label={dgettext("management", "GDR")}>{s.story_id}</:col>

        <:col :let={{s, _}} label={dgettext("management", "Position")}>{s.position}</:col>

        <:col :let={{s, _}} label={dgettext("management", "Name")}>{s.name}</:col>

        <:col :let={{_, count}} label={dgettext("management", "Topics")}>{count}</:col>

        <:action :let={{s, _}}>
          <.link
            phx-click="delete_section"
            phx-value-id={s.id}
            data-confirm={dgettext("management", "Delete this section and all its topics?")}
          >
            {dgettext("management", "Delete")}
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end
end
