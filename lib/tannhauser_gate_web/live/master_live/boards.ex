defmodule TannhauserGateWeb.MasterLive.Boards do
  @moduledoc """
  Master tools of the boards module: GDR announcements (title, Markdown text,
  pinned, optional expiry) shown on the GDR home, and the in-game notice
  boards hung in a room or in a whole zone, optionally restricted to a guild.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Boards, Guilds, Stories, Zones}
  alias TannhauserGate.Boards.{Announcement, Board}

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :boards}}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "Announcements and boards")
     |> assign(:locations, Stories.list_locations(story))
     |> assign(:zones, Zones.list_zones(story))
     |> assign(:guilds, if(Guilds.enabled?(story), do: Guilds.list_guilds(story), else: []))
     |> assign(:guilds?, Guilds.enabled?(story))
     |> load()
     |> edit_announcement(%Announcement{})
     |> edit_board(%Board{})}
  end

  defp story(socket), do: socket.assigns.current_story
  defp user(socket), do: socket.assigns.current_user

  defp load(socket) do
    socket
    |> assign(:announcements, Boards.list_all_announcements(story(socket)))
    |> assign(:boards, Boards.list_all_boards(story(socket)))
  end

  defp edit_announcement(socket, announcement) do
    socket
    |> assign(:announcement, announcement)
    |> assign(:announcement_form, to_form(Boards.change_announcement(announcement)))
  end

  defp edit_board(socket, board) do
    socket
    |> assign(:board, board)
    |> assign(:board_form, to_form(Boards.change_board(board)))
  end

  ## Announcements

  @impl true
  def handle_event("validate_announcement", %{"announcement" => params}, socket) do
    changeset =
      socket.assigns.announcement
      |> Boards.change_announcement(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :announcement_form, to_form(changeset))}
  end

  def handle_event("save_announcement", %{"announcement" => params}, socket) do
    result =
      case socket.assigns.announcement do
        %Announcement{id: nil} ->
          Boards.create_announcement(user(socket), story(socket), params)

        announcement ->
          Boards.update_announcement(user(socket), story(socket), announcement, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Announcement saved")
         |> load()
         |> edit_announcement(%Announcement{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :announcement_form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Boards.error_message(reason))}
    end
  end

  def handle_event("edit_announcement", %{"id" => id}, socket) do
    case Boards.get_announcement(story(socket), id) do
      nil -> {:noreply, put_flash(socket, :error, Boards.error_message(:not_found))}
      announcement -> {:noreply, edit_announcement(socket, announcement)}
    end
  end

  def handle_event("new_announcement", _params, socket),
    do: {:noreply, edit_announcement(socket, %Announcement{})}

  def handle_event("delete_announcement", %{"id" => id}, socket) do
    with %Announcement{} = announcement <- Boards.get_announcement(story(socket), id),
         {:ok, _} <- Boards.delete_announcement(user(socket), story(socket), announcement) do
      {:noreply,
       socket
       |> put_flash(:info, "Announcement deleted")
       |> load()
       |> edit_announcement(%Announcement{})}
    else
      nil -> {:noreply, put_flash(socket, :error, Boards.error_message(:not_found))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Boards.error_message(reason))}
    end
  end

  ## Boards

  def handle_event("validate_board", %{"board" => params}, socket) do
    changeset =
      socket.assigns.board
      |> Boards.change_board(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :board_form, to_form(changeset))}
  end

  def handle_event("save_board", %{"board" => params}, socket) do
    result =
      case socket.assigns.board do
        %Board{id: nil} -> Boards.create_board(user(socket), story(socket), params)
        board -> Boards.update_board(user(socket), story(socket), board, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Board saved")
         |> load()
         |> edit_board(%Board{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :board_form, to_form(changeset))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Boards.error_message(reason))}
    end
  end

  def handle_event("edit_board", %{"id" => id}, socket) do
    case Boards.get_board(story(socket), id) do
      nil -> {:noreply, put_flash(socket, :error, Boards.error_message(:not_found))}
      board -> {:noreply, edit_board(socket, board)}
    end
  end

  def handle_event("new_board", _params, socket),
    do: {:noreply, edit_board(socket, %Board{})}

  def handle_event("delete_board", %{"id" => id}, socket) do
    with %Board{} = board <- Boards.get_board(story(socket), id),
         {:ok, _} <- Boards.delete_board(user(socket), story(socket), board) do
      {:noreply,
       socket
       |> put_flash(:info, "Board taken down")
       |> load()
       |> edit_board(%Board{})}
    else
      nil -> {:noreply, put_flash(socket, :error, Boards.error_message(:not_found))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Boards.error_message(reason))}
    end
  end

  @impl true
  def handle_info({:boards, event, _payload}, socket) when event in [:announcement, :board],
    do: {:noreply, load(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

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
      <.header>
        Announcements and boards
        <:subtitle>
          Announcements appear on the GDR home; notice boards hang in a room or across a zone.
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/g/#{@current_story}/master"}
            class="btn btn-ghost btn-sm console-action"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Master tools
          </.link>
        </:actions>
      </.header>

      <div class="mt-8 grid gap-10 xl:grid-cols-2">
        <section id="master-announcements">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Announcements</h2>

          <.form
            for={@announcement_form}
            id="announcement-form"
            phx-change="validate_announcement"
            phx-submit="save_announcement"
            class="mt-3 rounded-xl border border-secondary/30 bg-base-200/70 p-5"
          >
            <.input
              field={@announcement_form[:title]}
              type="text"
              label="Title"
              maxlength="120"
              required
            />
            <.input
              field={@announcement_form[:body]}
              type="textarea"
              label="Text (Markdown)"
              rows="6"
              required
            />
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@announcement_form[:pinned]} type="checkbox" label="Pinned on top" />
              <.input
                field={@announcement_form[:expires_at]}
                type="datetime-local"
                label="Expires (optional, UTC)"
              />
            </div>
            <div class="flex gap-2">
              <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm console-action">
                {if @announcement.id, do: "Update announcement", else: "Post announcement"}
              </.button>
              <.button
                :if={@announcement.id}
                type="button"
                phx-click="new_announcement"
                class="btn btn-ghost btn-sm console-action"
              >
                Cancel
              </.button>
            </div>
          </.form>

          <p
            :if={@announcements == []}
            id="master-announcements-empty"
            class="mt-4 text-sm text-base-content/60"
          >
            No announcements yet.
          </p>
          <ul class="mt-4 space-y-2">
            <li
              :for={announcement <- @announcements}
              id={"master-announcement-#{announcement.id}"}
              class={[
                "flex items-start justify-between gap-3 rounded-lg border bg-base-200/50 px-4 py-3 transition hover:bg-base-200",
                if(Announcement.expired?(announcement, DateTime.utc_now()),
                  do: "border-base-content/10 opacity-60",
                  else: "border-secondary/20"
                )
              ]}
            >
              <div class="min-w-0">
                <p class="truncate font-semibold">
                  <.icon :if={announcement.pinned} name="hero-star-solid" class="size-4 text-warning" />
                  {announcement.title}
                </p>
                <p class="text-xs text-base-content/60">
                  {Calendar.strftime(announcement.inserted_at, "%d/%m/%Y %H:%M")}
                  <span :if={announcement.expires_at}>
                    · {if Announcement.expired?(announcement, DateTime.utc_now()),
                      do: "expired",
                      else: "expires"} {Calendar.strftime(announcement.expires_at, "%d/%m/%Y %H:%M")}
                  </span>
                </p>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  id={"announcement-edit-#{announcement.id}"}
                  type="button"
                  phx-click="edit_announcement"
                  phx-value-id={announcement.id}
                  class="btn btn-ghost btn-xs"
                >
                  Edit
                </button>
                <button
                  id={"announcement-delete-#{announcement.id}"}
                  type="button"
                  phx-click="delete_announcement"
                  phx-value-id={announcement.id}
                  data-confirm="Delete this announcement?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </div>
            </li>
          </ul>
        </section>

        <section id="master-boards-section">
          <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">Notice boards</h2>

          <.form
            for={@board_form}
            id="board-form"
            phx-change="validate_board"
            phx-submit="save_board"
            class="mt-3 rounded-xl border border-secondary/30 bg-base-200/70 p-5"
          >
            <.input field={@board_form[:name]} type="text" label="Name" maxlength="80" required />
            <.input
              field={@board_form[:description]}
              type="textarea"
              label="Description (optional)"
              rows="2"
            />
            <p class="mb-2 text-xs text-base-content/60">
              Hang it in one room, or across a whole zone (shown in every room of the zone).
            </p>
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={@board_form[:location_id]}
                type="select"
                label="Room"
                prompt="—"
                options={Enum.map(@locations, &{&1.name, &1.id})}
              />
              <.input
                field={@board_form[:zone_id]}
                type="select"
                label="Zone"
                prompt="—"
                options={Enum.map(@zones, &{&1.name, &1.id})}
              />
            </div>
            <.input
              :if={@guilds?}
              field={@board_form[:guild_id]}
              type="select"
              label="Restricted to guild (optional)"
              prompt="Everyone"
              options={Enum.map(@guilds, &{&1.name, &1.id})}
            />
            <div class="flex gap-2">
              <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm console-action">
                {if @board.id, do: "Update board", else: "Put up board"}
              </.button>
              <.button
                :if={@board.id}
                type="button"
                phx-click="new_board"
                class="btn btn-ghost btn-sm console-action"
              >
                Cancel
              </.button>
            </div>
          </.form>

          <p :if={@boards == []} id="master-boards-empty" class="mt-4 text-sm text-base-content/60">
            No notice boards yet.
          </p>
          <ul class="mt-4 space-y-2">
            <li
              :for={board <- @boards}
              id={"master-board-#{board.id}"}
              class="flex items-start justify-between gap-3 rounded-lg border border-secondary/20 bg-base-200/50 px-4 py-3 transition hover:bg-base-200"
            >
              <div class="min-w-0">
                <.link
                  navigate={~p"/g/#{@current_story}/boards?board=#{board.id}"}
                  class="truncate font-semibold hover:text-primary"
                >
                  {board.name}
                </.link>
                <p class="text-xs text-base-content/60">
                  {Boards.place_label(board)}
                  <span :if={board.guild}>· {board.guild.name} only</span>
                </p>
              </div>
              <div class="flex shrink-0 gap-1">
                <button
                  id={"board-edit-#{board.id}"}
                  type="button"
                  phx-click="edit_board"
                  phx-value-id={board.id}
                  class="btn btn-ghost btn-xs"
                >
                  Edit
                </button>
                <button
                  id={"board-delete-#{board.id}"}
                  type="button"
                  phx-click="delete_board"
                  phx-value-id={board.id}
                  data-confirm="Take this board down with all its notices?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  Delete
                </button>
              </div>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
