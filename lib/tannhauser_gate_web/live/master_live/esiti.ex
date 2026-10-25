defmodule TannhauserGateWeb.MasterLive.Esiti do
  @moduledoc """
  The masters' queue of esiti (esiti module): the requests of the GDR
  filtered by status (active, open, claimed by me, in progress, resolved,
  closed, all), with live updates and quick claim/release buttons. Each
  request opens on its page, where masters discuss and resolve it.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.EsitiComponents

  alias TannhauserGate.Esiti

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :esiti}}

  @filters [
    {"active", "Active"},
    {"open", "Open"},
    {"mine", "Mine"},
    {"claimed", "In progress"},
    {"resolved", "Resolved"},
    {"closed", "Closed"},
    {"all", "All"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    if connected?(socket), do: Esiti.subscribe(story.id)

    {:ok,
     socket
     |> assign(:page_title, "Esiti queue")
     |> assign(:filters, @filters)
     |> assign(:status, "active")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status =
      if params["status"] in Enum.map(@filters, &elem(&1, 0)),
        do: params["status"],
        else: "active"

    {:noreply, socket |> assign(:status, status) |> load()}
  end

  defp load(socket) do
    %{current_story: story, current_user: user, status: status} = socket.assigns
    esiti = Esiti.list_queue(story, status, user)

    socket
    |> assign(:counts, Esiti.status_counts(story))
    |> assign(:empty?, esiti == [])
    |> stream(:esiti, esiti, reset: true)
  end

  @impl true
  def handle_event("claim", %{"id" => id}, socket),
    do: transition(socket, id, &Esiti.claim/3, "You took the request.")

  def handle_event("release", %{"id" => id}, socket),
    do: transition(socket, id, &Esiti.release/3, "Request back in the queue.")

  defp transition(socket, id, fun, message) do
    %{current_story: story, current_user: user} = socket.assigns

    result =
      case Esiti.get_esito(story, id) do
        nil -> {:error, :esito_not_found}
        esito -> fun.(user, story, esito)
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, message) |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Esiti.error_message(reason)) |> load()}
    end
  end

  @impl true
  def handle_info({:esiti, _event, _esito}, socket), do: {:noreply, load(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp count(counts, "active"), do: Map.get(counts, "open", 0) + Map.get(counts, "claimed", 0)
  defp count(counts, "all"), do: counts |> Map.values() |> Enum.sum()
  defp count(_counts, "mine"), do: nil
  defp count(counts, status), do: Map.get(counts, status, 0)

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
      <div class="mb-4">
        <.link
          navigate={~p"/g/#{@current_story}/master"}
          class="text-sm font-semibold text-secondary hover:text-primary"
        >
          <.icon name="hero-arrow-left-solid" class="size-3" /> Master tools
        </.link>
      </div>

      <.header>
        Esiti queue
        <:subtitle>
          Action requests filed by the players. Claim one to handle it, discuss it in its
          thread and resolve it with an outcome, dice and rewards.
        </:subtitle>
      </.header>

      <nav id="esiti-filters" class="mt-6 flex flex-wrap gap-2">
        <.link
          :for={{key, label} <- @filters}
          id={"esiti-filter-#{key}"}
          patch={~p"/g/#{@current_story}/master/esiti?status=#{key}"}
          class={[
            "btn btn-sm transition",
            if(@status == key, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          {label}
          <span :if={count(@counts, key)} class="badge badge-xs badge-soft">
            {count(@counts, key)}
          </span>
        </.link>
      </nav>

      <p :if={@empty?} id="esiti-queue-empty" class="mt-6 text-sm text-base-content/60">
        Nothing here.
      </p>

      <ul id="esiti-queue" phx-update="stream" class="mt-4 space-y-2">
        <li
          :for={{dom_id, esito} <- @streams.esiti}
          id={dom_id}
          class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-secondary/20 bg-base-200/60 p-4 transition hover:border-primary/40"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <.status_badge status={esito.status} />
              <.link
                navigate={~p"/g/#{@current_story}/esiti/#{esito.id}"}
                class="truncate font-semibold text-primary hover:underline"
              >
                {esito.title}
              </.link>
            </div>
            <p class="mt-1 text-xs text-base-content/60">
              {esito.character.name}
              <span :if={place(esito)}>· {place(esito)}</span> · {when_label(esito.inserted_at)}
              <span :if={esito.claimed_by}>· {esito.claimed_by.username}</span>
            </p>
          </div>
          <div class="flex gap-2">
            <button
              :if={esito.status == "open"}
              id={"claim-#{esito.id}"}
              phx-click="claim"
              phx-value-id={esito.id}
              class="btn btn-sm btn-secondary"
            >
              <.icon name="hero-hand-raised" class="size-4" /> Claim
            </button>
            <button
              :if={esito.status == "claimed"}
              id={"release-#{esito.id}"}
              phx-click="release"
              phx-value-id={esito.id}
              class="btn btn-sm btn-ghost"
            >
              Release
            </button>
            <.link
              :if={esito.status in ["open", "claimed"]}
              id={"resolve-#{esito.id}"}
              navigate={~p"/g/#{@current_story}/esiti/#{esito.id}"}
              class="btn btn-sm btn-primary btn-soft"
            >
              Resolve →
            </.link>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
