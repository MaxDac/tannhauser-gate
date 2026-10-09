defmodule TannhauserGateWeb.GdrLive.Index do
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.{Accounts, Stories}
  alias TannhauserGate.Stories.Themes

  @impl true
  def mount(_params, _session, socket) do
    stories = Stories.list_visible_stories(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Choose your GDR")
     |> assign(:empty?, stories == [])
     |> stream(:stories, stories)}
  end

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
        Choose your GDR
        <:subtitle>Every game master runs their own world. Pick one to enter.</:subtitle>

        <:actions>
          <.button :if={@current_user.gm} id="my-gdr-link" navigate={~p"/gdrs/request"}>
            <.icon name="hero-sparkles" class="size-4" /> My GDR
          </.button>

          <.button :if={Accounts.admin?(@current_user)} id="admin-link" navigate={~p"/admin"}>
            Admin
          </.button>
        </:actions>
      </.header>

      <p
        :if={@empty?}
        id="no-gdrs"
        class="mt-10 rounded-lg border border-dashed border-secondary/30 p-8 text-center text-base-content/60"
      >
        No GDR is open yet.
      </p>

      <div id="gdrs" phx-update="stream" class="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={{dom_id, story} <- @streams.stories}
          id={dom_id}
          navigate={~p"/g/#{story}"}
          data-theme={story.theme}
          style={Themes.style(story.theme_overrides)}
          class="group flex flex-col gap-2 rounded-xl border border-primary/30 bg-base-200 p-5 transition hover:-translate-y-0.5 hover:border-primary hover:shadow-phosphor"
        >
          <p class="text-lg font-bold text-primary">{story.name}</p>

          <p class="line-clamp-3 text-sm text-base-content/70">{story.summary}</p>

          <p class="mt-auto flex items-center justify-between pt-2 text-xs uppercase tracking-wider text-secondary">
            <span>GM {(story.owner && story.owner.username) || "Platform"}</span>
            <span :if={story.status == "draft"} class="badge badge-warning badge-sm">Draft</span>
          </p>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
