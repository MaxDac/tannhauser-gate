defmodule TannhauserGateWeb.MasterLive.ChatLog do
  @moduledoc """
  The chat log of a GDR for its masters: live and archived entries of every
  room, filtered by room and date range.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.ChatComponents

  alias TannhauserGate.{Chat, Stories}

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story

    {:ok,
     socket
     |> assign(:page_title, "Chat log")
     |> assign(:locations, Stories.list_locations(story))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, ["location_id", "from", "to"])
    entries = Chat.search_log(socket.assigns.current_story.id, filters)

    {:noreply,
     socket
     |> assign(:filter_form, to_form(filters, as: "filters"))
     |> assign(:count, length(entries))
     |> stream(:entries, entries, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    query = filters |> Map.take(["location_id", "from", "to"]) |> Map.reject(&(elem(&1, 1) == ""))

    {:noreply,
     push_patch(socket, to: ~p"/g/#{socket.assigns.current_story}/master/chat-log?#{query}")}
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
      mail_unread={@mail_unread}
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
        Chat log
        <:subtitle>
          Every room of {@current_story.name}, including archived messages (newest first, up to 200).
        </:subtitle>
      </.header>

      <.form
        for={@filter_form}
        id="chat-log-filters"
        phx-submit="filter"
        class="mt-6 grid gap-3 rounded-xl border border-secondary/20 bg-base-200/80 p-4 sm:grid-cols-4"
      >
        <.input
          field={@filter_form[:location_id]}
          type="select"
          label="Room"
          prompt="All rooms"
          options={Enum.map(@locations, &{&1.name, &1.id})}
        /> <.input field={@filter_form[:from]} type="date" label="From" />
        <.input field={@filter_form[:to]} type="date" label="To" />
        <div class="flex items-end">
          <.button id="chat-log-search" class="btn btn-primary console-action mb-2 w-full">
            <.icon name="hero-magnifying-glass" class="size-4" /> Search
          </.button>
        </div>
      </.form>

      <p id="chat-log-count" class="mt-4 text-xs text-base-content/60">{@count} entries</p>

      <ol id="chat-log" phx-update="stream" class="mt-2 space-y-2">
        <li
          id="chat-log-empty"
          class="hidden py-8 text-center text-sm text-base-content/60 only:block"
        >
          No messages match these filters.
        </li>

        <li
          :for={{dom_id, entry} <- @streams.entries}
          id={dom_id}
          class={[
            "chat-log-entry rounded-lg border bg-base-200/80 p-3 transition hover:border-secondary/50",
            if(entry.archived?, do: "border-fog-700/50", else: "border-secondary/20")
          ]}
        >
          <p class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-base-content/60">
            <time class="font-mono" datetime={DateTime.to_iso8601(entry.inserted_at)}>
              {Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M")}
            </time>
            <span class="font-semibold text-primary">{entry.speaker}</span>
            <span :if={entry.username}>({entry.username})</span>
            in <span class="font-semibold">{entry.location.name}</span>
            <.kind_badge kind={entry.kind} />
            <span
              :if={entry.archived?}
              class="archived-badge rounded bg-fog-700/60 px-1.5 py-0.5 text-[0.65rem] font-bold uppercase tracking-widest text-fog-300"
            >
              Archived
            </span>
          </p>

          <.dice_result
            :if={entry.kind == "dice" && entry.data}
            id={"log-dice-#{entry.id}"}
            result={entry.data}
          />
          <p :if={entry.kind != "dice"} class="mt-1 whitespace-pre-line break-words text-sm">
            {entry.body}
          </p>
        </li>
      </ol>
    </Layouts.app>
    """
  end
end
