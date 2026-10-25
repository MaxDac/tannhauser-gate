defmodule TannhauserGateWeb.GuideLive do
  @moduledoc "Reads the GDR guide: its sections and Markdown pages."
  use TannhauserGateWeb, :live_view

  alias TannhauserGate.Guide

  @impl true
  def mount(_params, _session, socket) do
    story = socket.assigns.current_story
    {:ok, assign(socket, sections: Guide.list_sections(story), page_title: "Guide")}
  end

  @impl true
  def handle_params(%{"page_id" => id}, _uri, socket) do
    page = Guide.get_page!(socket.assigns.current_story, id)
    {:noreply, assign(socket, page: page, page_title: page.title)}
  end

  def handle_params(_params, _uri, socket) do
    case socket.assigns.sections |> Enum.flat_map(& &1.pages) |> List.first() do
      nil ->
        {:noreply, assign(socket, :page, nil)}

      page ->
        {:noreply,
         push_patch(socket, to: ~p"/g/#{socket.assigns.current_story}/guide/#{page.id}")}
    end
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
      last_location={@last_location}
      mail_unread={@mail_unread}
      announcements_unread={@announcements_unread}
    >
      <.header>
        Guide
        <:subtitle>The world of {@current_story.name}: its background, rules and customs.</:subtitle>
        <:actions :if={TannhauserGate.Stories.admin_role?(@story_role)}>
          <.button id="guide-edit-link" navigate={~p"/g/#{@current_story}/gm/guide"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit the guide
          </.button>
        </:actions>
      </.header>

      <p
        :if={@sections == [] or is_nil(@page)}
        id="guide-empty"
        class="mt-8 rounded-md border border-secondary/20 p-6 text-center text-base-content/60"
      >
        The guide of this GDR is still being written.
      </p>

      <div :if={@page} class="mt-8 grid gap-8 lg:grid-cols-[16rem_1fr]">
        <aside class="lg:sticky lg:top-6 lg:self-start">
          <.guide_toc
            id="guide-toc"
            story={@current_story}
            sections={@sections}
            current_page_id={@page.id}
          />
        </aside>

        <article
          id="guide-page"
          class="rounded-xl border border-secondary/20 bg-base-200/70 p-6 shadow-sm"
        >
          <h2 id="guide-page-title" class="text-2xl font-bold text-primary">{@page.title}</h2>
          <.markdown id="guide-page-body" content={@page.body} class="mt-4" />
        </article>
      </div>
    </Layouts.app>
    """
  end
end
