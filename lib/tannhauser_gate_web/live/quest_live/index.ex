defmodule TannhauserGateWeb.QuestLive.Index do
  @moduledoc """
  The quest registry of a GDR (quests module): the recorded quests with
  their summary, master, room and participants. Players see the public ones;
  masters see all of them, with a link to the chat log of the quest's range.
  """
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Quests
  alias TannhauserGate.Quests.Quest

  on_mount {TannhauserGateWeb.UserAuth, {:require_module, :quests}}

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(TannhauserGate.PubSub, Quests.topic(story.id))

    {:ok,
     socket
     |> assign(:page_title, "Quests · #{story.name}")
     |> assign(:quests, Quests.list_quests(story, user))}
  end

  @impl true
  def handle_info({:quests, _event, _quest}, socket) do
    %{current_user: user, current_story: story} = socket.assigns
    {:noreply, assign(socket, :quests, Quests.list_quests(story, user))}
  end

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
        Quests
        <:subtitle>The chronicle of the quests run in {@current_story.name}.</:subtitle>
        <:actions :if={@master?}>
          <.link
            id="quests-manage"
            navigate={~p"/g/#{@current_story}/master/quests"}
            class="btn btn-sm btn-secondary btn-soft"
          >
            <.icon name="hero-pencil-square" class="size-4" /> Manage
          </.link>
        </:actions>
      </.header>

      <p :if={@quests == []} id="quests-empty" class="mt-6 text-sm text-base-content/60">
        No quests recorded yet.
      </p>

      <ol id="quest-registry" class="relative mt-6 space-y-4 border-l border-secondary/30 pl-6">
        <li :for={quest <- @quests} id={"quest-#{quest.id}"} class="relative">
          <span class="absolute -left-[1.85rem] top-5 size-3 rounded-full border-2 border-primary bg-base-100" />
          <article class="rounded-xl border border-secondary/20 bg-base-200/60 p-5 transition hover:border-primary/40">
            <header class="flex flex-wrap items-start justify-between gap-2">
              <div>
                <h2 class="text-lg font-semibold text-primary">{quest.title}</h2>
                <p class="text-xs text-base-content/60">
                  {quest.game_date_label || Calendar.strftime(quest.held_on, "%d/%m/%Y")}
                  <span :if={quest.location}>
                    · <.icon name="hero-map-pin-micro" class="size-3" /> {quest.location.name}
                  </span>
                  <span :if={quest.master}>· run by {quest.master.username}</span>
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <span
                  :if={quest.visibility == "masters"}
                  id={"quest-#{quest.id}-masters-only"}
                  class="badge badge-soft badge-sm badge-warning"
                >
                  <.icon name="hero-eye-slash-micro" class="size-3" /> masters only
                </span>
                <.link
                  :if={@master? && Quests.chat_log_params(quest)}
                  id={"quest-#{quest.id}-log"}
                  navigate={~p"/g/#{@current_story}/master/chat-log?#{Quests.chat_log_params(quest)}"}
                  class="btn btn-xs btn-ghost"
                >
                  <.icon name="hero-document-text" class="size-3" /> Chat log
                </.link>
              </div>
            </header>
            <.markdown
              :if={quest.summary not in [nil, ""]}
              id={"quest-#{quest.id}-summary"}
              content={quest.summary}
              class="prose-sm mt-3"
            />
            <div :if={quest.participants != []} class="mt-3 flex flex-wrap gap-2">
              <.link
                :for={p <- quest.participants}
                id={"quest-#{quest.id}-participant-#{p.character_id}"}
                navigate={~p"/g/#{@current_story}/characters/#{p.character}"}
                class="badge badge-outline badge-secondary gap-1 transition hover:badge-primary"
              >
                <.icon name="hero-user-micro" class="size-3" /> {p.character.name}
              </.link>
            </div>
            <p
              :if={@master? && Quest.rewarded?(quest)}
              class="mt-2 text-xs text-success"
            >
              <.icon name="hero-check-badge-micro" class="size-3" /> rewards handed out
            </p>
          </article>
        </li>
      </ol>
    </Layouts.app>
    """
  end
end
