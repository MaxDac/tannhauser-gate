defmodule TannhauserGateWeb.BoardLive.Index do
  @moduledoc """
  Every notice board of the GDR the user can see (boards module), with their
  notices. Players pin short in-character notices as one of their playable
  characters; authors remove their notices, masters remove any. Guild boards
  are shown only to the guild's members and the masters.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Boards
  alias TannhauserGate.Boards.Notice

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :boards}}

  @impl true
  def mount(_params, _session, socket) do
    %{current_story: story, current_user: user} = socket.assigns

    {:ok,
     socket
     |> assign(:page_title, "Notice boards")
     |> assign(:characters, Boards.posting_characters(user, story))
     |> assign(:posting_to, nil)
     |> assign(:highlight, nil)
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :highlight, params["board"])}
  end

  defp load(socket) do
    %{current_story: story, current_user: user} = socket.assigns
    boards = Boards.list_boards(story, user)

    socket
    |> assign(:boards, boards)
    |> assign(:notices, Boards.notices_by_board(boards))
  end

  @impl true
  def handle_event("open_notice", %{"board" => board_id}, socket) do
    %{current_story: story, current_user: user} = socket.assigns

    case Boards.get_board(story, board_id) do
      %{} = board ->
        if Boards.accessible?(user, story, board) do
          {:noreply,
           socket
           |> assign(:posting_to, board.id)
           |> assign(:form, notice_form(Boards.change_notice(%Notice{})))}
        else
          {:noreply, put_flash(socket, :error, Boards.error_message(:unauthorized))}
        end

      nil ->
        {:noreply, put_flash(socket, :error, Boards.error_message(:not_found))}
    end
  end

  def handle_event("cancel_notice", _params, socket),
    do: {:noreply, assign(socket, :posting_to, nil)}

  def handle_event("validate_notice", %{"notice" => params}, socket) do
    changeset =
      %Notice{}
      |> Boards.change_notice(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, notice_form(changeset, params))}
  end

  def handle_event("post_notice", %{"notice" => params}, socket) do
    %{current_story: story, current_user: user, posting_to: board_id} = socket.assigns

    with %{} = board <- Boards.get_board(story, board_id),
         {:ok, _notice} <- Boards.post_notice(user, story, board, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Notice pinned")
       |> assign(:posting_to, nil)
       |> load()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, Boards.error_message(:not_found))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, notice_form(changeset, params))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Boards.error_message(reason))}
    end
  end

  def handle_event("delete_notice", %{"id" => id}, socket) do
    %{current_story: story, current_user: user} = socket.assigns

    with %Notice{} = notice <- Boards.get_notice(story, id),
         {:ok, _} <- Boards.delete_notice(user, story, notice) do
      {:noreply, socket |> put_flash(:info, "Notice removed") |> load()}
    else
      nil -> {:noreply, put_flash(socket, :error, Boards.error_message(:not_found))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Boards.error_message(reason))}
    end
  end

  # The character pick is not a Notice field: keep it in the form params.
  defp notice_form(changeset, params \\ %{}) do
    form = to_form(changeset)
    %{form | params: Map.merge(form.params, Map.take(params, ["character_id"]))}
  end

  @impl true
  def handle_info({:boards, event, _payload}, socket) when event in [:board, :notice],
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
        Notice boards
        <:subtitle>
          In-character notices pinned around {@current_story.name}.
        </:subtitle>
        <:actions :if={MapSet.member?(@permissions, :can_manage_world)}>
          <.link
            id="boards-manage"
            navigate={~p"/g/#{@current_story}/master/boards"}
            class="btn btn-ghost btn-sm console-action"
          >
            <.icon name="hero-wrench-screwdriver" class="size-4" /> Manage
          </.link>
        </:actions>
      </.header>

      <p :if={@boards == []} id="boards-empty" class="mt-8 text-center text-base-content/60">
        No notice boards have been put up yet.
      </p>

      <div id="boards" class="mt-6 grid gap-6 lg:grid-cols-2">
        <section
          :for={board <- @boards}
          id={"board-#{board.id}"}
          class={[
            "rounded-xl border bg-base-200/70 p-5 shadow-lg transition",
            if(@highlight == to_string(board.id),
              do: "border-primary ring-2 ring-primary/40",
              else: "border-secondary/25 hover:border-secondary/50"
            )
          ]}
        >
          <header class="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h2 class="font-display text-lg font-bold uppercase tracking-[0.15em] text-primary">
                {board.name}
              </h2>
              <p class="text-xs uppercase tracking-wider text-secondary">
                <.icon name="hero-map-pin-micro" class="size-3" /> {Boards.place_label(board)}
                <span
                  :if={board.guild}
                  id={"board-#{board.id}-guild"}
                  class="ml-2 rounded border border-warning/50 px-1.5 text-warning"
                >
                  {board.guild.name} only
                </span>
              </p>
            </div>
            <.button
              :if={@characters != [] and @posting_to != board.id}
              id={"board-#{board.id}-post"}
              phx-click="open_notice"
              phx-value-board={board.id}
              class="btn btn-primary btn-sm console-action"
            >
              <.icon name="hero-paper-clip" class="size-4" /> Pin a notice
            </.button>
          </header>
          <p :if={board.description} class="mt-2 text-sm text-base-content/70">
            {board.description}
          </p>

          <.form
            :if={@posting_to == board.id}
            for={@form}
            id={"notice-form-#{board.id}"}
            phx-change="validate_notice"
            phx-submit="post_notice"
            class="mt-4 rounded-lg border border-primary/30 bg-base-100/60 p-4"
          >
            <.input
              field={@form[:character_id]}
              type="select"
              label="Signed by"
              options={Enum.map(@characters, &{&1.name, &1.id})}
            />
            <.input field={@form[:title]} type="text" label="Title (optional)" maxlength="80" />
            <.input
              field={@form[:body]}
              type="textarea"
              label="Notice (Markdown)"
              rows="4"
              maxlength="1000"
              required
            />
            <.input
              field={@form[:expires_at]}
              type="datetime-local"
              label="Take it down on (optional, UTC)"
            />
            <div class="flex gap-2">
              <.button phx-disable-with="Pinning..." class="btn btn-primary btn-sm console-action">
                Pin it
              </.button>
              <.button
                type="button"
                phx-click="cancel_notice"
                class="btn btn-ghost btn-sm console-action"
              >
                Cancel
              </.button>
            </div>
          </.form>

          <ul class="mt-4 grid gap-3 sm:grid-cols-2">
            <li
              :if={Map.get(@notices, board.id, []) == []}
              id={"board-#{board.id}-empty"}
              class="text-sm text-base-content/50 sm:col-span-2"
            >
              Nothing pinned here.
            </li>
            <li
              :for={{notice, index} <- Enum.with_index(Map.get(@notices, board.id, []))}
              id={"notice-#{notice.id}"}
              class={[
                "board-notice group relative transition hover:z-10 hover:rotate-0 hover:scale-[1.02]",
                if(rem(index, 2) == 0, do: "-rotate-1", else: "rotate-1")
              ]}
            >
              <.notice_card notice={notice} />
              <.report_link
                :if={
                  TannhauserGate.Reports.enabled?(@current_story) and
                    notice.user_id != @current_user.id
                }
                id={"notice-report-#{notice.id}"}
                story={@current_story}
                type="notice"
                target_id={notice.id}
                return_to={~p"/g/#{@current_story}/boards"}
                class="absolute right-8 top-2 rounded-full p-1 opacity-50 group-hover:opacity-100"
              />
              <button
                :if={Boards.can_delete_notice?(@current_user, @current_story, notice)}
                id={"notice-delete-#{notice.id}"}
                type="button"
                phx-click="delete_notice"
                phx-value-id={notice.id}
                data-confirm="Take this notice down?"
                class="absolute right-2 top-2 rounded-full p-1 text-error opacity-50 transition hover:bg-error/10 group-hover:opacity-100"
                aria-label="Take the notice down"
              >
                <.icon name="hero-trash-micro" class="size-4" />
              </button>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :notice, :map, required: true
  attr :id, :string, default: nil

  @doc "A paper notice: optional title, Markdown text, signature and expiry."
  def notice_card(assigns) do
    ~H"""
    <article id={@id} class="rounded-md bg-[#f3eed8] p-3 pr-8 text-[#2b2618] shadow-md">
      <h3 :if={@notice.title} class="font-bold">{@notice.title}</h3>
      <.markdown content={@notice.body} class="text-sm" />
      <p class="mt-2 text-right text-xs italic opacity-70">
        — {@notice.character.name}
        <span :if={@notice.expires_at}>
          · until {Calendar.strftime(@notice.expires_at, "%d/%m %H:%M")}
        </span>
      </p>
    </article>
    """
  end
end
