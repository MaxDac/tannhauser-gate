defmodule TannhauserGateWeb.GdrLive.Ranking do
  @moduledoc """
  The portal ranking: the most voted published GDRs this month and over the
  last 12 months, ties broken by average review score.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.DirectoryComponents

  alias TannhauserGate.Directory

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    {:ok,
     socket
     |> assign(:page_title, dgettext("player", "Ranking"))
     |> assign(:month_label, format_local_date(today, "%B %Y"))
     |> assign(:month, Directory.ranking(:month, today))
     |> assign(:year, Directory.ranking(:year, today))}
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
    >
      <.link
        navigate={~p"/gdrs"}
        id="back-to-directory"
        class="inline-flex items-center gap-1 text-xs uppercase tracking-wider text-base-content/60 transition hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="size-3.5" /> {dgettext("player", "Directory")}
      </.link>

      <.header>
        <span class="inline-flex items-center gap-2">
          <.icon name="hero-trophy" class="size-6 text-warning" /> {dgettext("player", "Ranking")}
        </span>

        <:subtitle>
          {dgettext(
            "player",
            "The GDRs the players voted the most. Everyone can vote once a month for each GDR."
          )}
        </:subtitle>
      </.header>

      <div class="mt-8 grid gap-8 lg:grid-cols-2">
        <.ranking_list
          id="ranking-month"
          title={dgettext("player", "This month · %{month_label}", month_label: @month_label)}
          entries={@month}
        />
        <.ranking_list id="ranking-year" title={dgettext("player", "Last 12 months")} entries={@year} />
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :entries, :list, required: true

  defp ranking_list(assigns) do
    ~H"""
    <section id={@id} class="rounded-2xl border border-base-content/10 bg-base-200 p-5">
      <h2 class="text-xs font-bold uppercase tracking-[0.25em] text-secondary">{@title}</h2>

      <p
        :if={@entries == []}
        id={"#{@id}-empty"}
        class="mt-4 rounded-xl border border-dashed border-secondary/30 p-6 text-center text-sm text-base-content/60"
      >
        {dgettext("player", "No votes yet.")}
      </p>

      <ol class="mt-4 space-y-2">
        <li :for={entry <- @entries} id={"#{@id}-#{entry.id}"}>
          <.link
            navigate={~p"/gdrs/#{entry.id}"}
            class="group flex items-center gap-4 rounded-xl border border-transparent px-3 py-2 transition hover:-translate-y-0.5 hover:border-primary/40 hover:bg-base-100/60"
          >
            <span class={[
              "flex size-9 shrink-0 items-center justify-center rounded-full font-mono text-sm font-bold",
              rank_class(entry.rank)
            ]}>
              {entry.rank}
            </span>

            <span class="min-w-0 flex-1">
              <span class="block truncate font-bold text-primary">{entry.story.name}</span>
              <span class="flex items-center gap-2 text-xs text-base-content/60">
                <.lifecycle_badge lifecycle={entry.story.lifecycle} />
                <.score score={entry.score} count={entry.review_count} />
              </span>
            </span>

            <span class="text-right">
              <span id={"#{@id}-#{entry.id}-votes"} class="block font-mono text-lg font-bold">
                {entry.votes}
              </span>

              <span class="text-[0.65rem] uppercase tracking-wider text-base-content/50">
                {dngettext("player", "vote", "votes", entry.votes)}
              </span>
            </span>
          </.link>
        </li>
      </ol>
    </section>
    """
  end

  defp rank_class(1), do: "bg-warning text-warning-content"
  defp rank_class(2), do: "bg-base-content/70 text-base-100"
  defp rank_class(3), do: "bg-orange-700 text-white"
  defp rank_class(_), do: "bg-base-300 text-base-content/70"
end
