defmodule TannhauserGateWeb.ForumLive.Index do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Forum

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Forum")
     |> assign(:sections, Forum.list_sections())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Forum
      <:subtitle>Out of the rain: talk, plan and gossip.</:subtitle>
    </.header>

    <p :if={@sections == []} class="mt-8 text-slate-400">No sections yet.</p>

    <ul id="forum-sections" class="mt-8 space-y-3">
      <li :for={{section, topic_count} <- @sections}>
        <.link
          navigate={~p"/forum/sections/#{section}"}
          class="flex items-center justify-between gap-4 rounded-xl border border-teal/20 bg-ink/80 p-4 transition hover:border-neon/60 hover:shadow-neon"
        >
          <div>
            <p class="text-lg font-bold text-slate-100">{section.name}</p>
            <p class="text-sm text-slate-400">{section.description}</p>
          </div>
          <span class="shrink-0 text-xs uppercase tracking-wider text-teal">
            {topic_count} {if topic_count == 1, do: "topic", else: "topics"}
          </span>
        </.link>
      </li>
    </ul>
    """
  end
end
