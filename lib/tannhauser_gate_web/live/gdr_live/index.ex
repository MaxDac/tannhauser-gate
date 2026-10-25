defmodule TannhauserGateWeb.GdrLive.Index do
  @moduledoc """
  The portal directory: the GDRs the user can see, as cards with their
  listing (banner, pitch, genres, lifecycle, rating) and activity (score,
  members, users online, votes this month), filtered and sorted through URL
  params.
  """
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.DirectoryComponents

  alias TannhauserGate.{Accounts, Directory}
  alias TannhauserGateWeb.{GdrPresence, Presence}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Choose your GDR")
     |> stream_configure(:gdrs, dom_id: &"gdrs-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Directory.normalize_filters(params)

    entries =
      Directory.list_directory(socket.assigns.current_user, filters, online: &online_count/1)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(
       :filtered?,
       Enum.any?(Map.delete(filters, "sort"), fn {_, v} -> v not in [nil, ""] end)
     )
     |> assign(:count, length(entries))
     |> stream(:gdrs, entries, reset: true)}
  end

  @doc false
  def online_count(story_id), do: story_id |> GdrPresence.topic() |> Presence.list() |> map_size()

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/gdrs?#{query_params(params)}")}
  end

  defp query_params(params) do
    params
    |> Directory.normalize_filters()
    |> Enum.reject(fn {key, value} ->
      value in [nil, ""] or (key == "sort" and value == "top")
    end)
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
      <section class="relative overflow-hidden rounded-2xl border border-primary/20 bg-gradient-to-br from-base-200 via-base-200 to-primary/10 px-6 py-8 sm:px-10">
        <div class="pointer-events-none absolute -right-16 -top-16 size-64 rounded-full bg-primary/10 blur-3xl" />
        <div class="relative flex flex-wrap items-end justify-between gap-6">
          <div class="max-w-2xl">
            <p class="text-xs font-bold uppercase tracking-[0.3em] text-secondary">GDR directory</p>
            <h1 class="mt-2 text-3xl font-bold text-base-content sm:text-4xl">Choose your GDR</h1>
            <p class="mt-2 text-sm text-base-content/70">
              Every game master runs their own world. Browse by genre and status, read the
              players' reviews, vote for your favourites and step in.
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <.button id="ranking-link" navigate={~p"/gdrs/ranking"}>
              <.icon name="hero-trophy" class="size-4" /> Ranking
            </.button>
            <.button :if={@current_user.gm} id="my-gdr-link" navigate={~p"/gdrs/request"}>
              <.icon name="hero-sparkles" class="size-4" /> My GDR
            </.button>
            <.button :if={Accounts.admin?(@current_user)} id="admin-link" navigate={~p"/admin"}>
              Admin
            </.button>
          </div>
        </div>
      </section>

      <.form
        for={@filter_form}
        id="directory-filters"
        phx-change="filter"
        phx-submit="filter"
        class="mt-6 grid gap-x-3 rounded-xl border border-secondary/20 bg-base-200/70 px-4 pt-3 sm:grid-cols-2 lg:grid-cols-[2fr_repeat(4,1fr)]"
      >
        <.input
          field={@filter_form[:q]}
          type="search"
          label="Search"
          placeholder="Name, pitch or summary"
          phx-debounce="300"
        />
        <.input
          field={@filter_form[:genre]}
          type="select"
          label="Genre"
          prompt="All genres"
          options={for {value, label} <- Directory.genres(), do: {label, value}}
        />
        <.input
          field={@filter_form[:lifecycle]}
          type="select"
          label="Status"
          prompt="Any status"
          options={for {value, label} <- Directory.lifecycles(), do: {label, value}}
        />
        <.input
          field={@filter_form[:rating]}
          type="select"
          label="Rating"
          prompt="Any rating"
          options={for {value, label} <- Directory.content_ratings(), do: {label, value}}
        />
        <.input
          field={@filter_form[:sort]}
          type="select"
          label="Sort by"
          options={for {value, label} <- Directory.sorts(), do: {label, value}}
        />
      </.form>

      <div class="mt-4 flex items-center justify-between text-xs text-base-content/60">
        <p id="directory-count">{@count} {if @count == 1, do: "GDR", else: "GDRs"}</p>
        <.link
          :if={@filtered?}
          id="reset-filters"
          patch={~p"/gdrs"}
          class="inline-flex items-center gap-1 transition hover:text-primary"
        >
          <.icon name="hero-x-mark" class="size-3.5" /> Clear filters
        </.link>
      </div>

      <p
        :if={@count == 0}
        id="no-gdrs"
        class="mt-6 rounded-xl border border-dashed border-secondary/30 p-10 text-center text-base-content/60"
      >
        {if @filtered?, do: "No GDR matches these filters.", else: "No GDR is open yet."}
      </p>

      <div id="gdrs" phx-update="stream" class="mt-4 grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
        <article
          :for={{dom_id, entry} <- @streams.gdrs}
          id={dom_id}
          class="group relative flex flex-col overflow-hidden rounded-2xl border border-base-content/10 bg-base-200 shadow-sm transition duration-300 hover:-translate-y-1 hover:border-primary/50 hover:shadow-phosphor focus-within:border-primary/50"
        >
          <.banner story={entry.story}>
            <div class="absolute inset-x-3 top-3 flex items-start justify-between gap-2">
              <div class="flex flex-wrap gap-1.5">
                <.lifecycle_badge lifecycle={entry.story.lifecycle} />
                <span
                  :if={entry.story.status == "draft"}
                  class="rounded-full border border-warning/50 bg-base-100/70 px-2 py-0.5 text-[0.65rem] font-bold uppercase tracking-wider text-warning"
                >
                  Draft
                </span>
              </div>
              <.rating_badge rating={entry.story.content_rating} />
            </div>
          </.banner>

          <div class="flex flex-1 flex-col gap-3 p-5 pt-1">
            <h2 class="text-lg font-bold leading-tight text-primary">
              <.link
                navigate={~p"/gdrs/#{entry.id}"}
                id={"gdr-profile-link-#{entry.id}"}
                class="after:absolute after:inset-0 focus:outline-none"
              >
                {entry.story.name}
              </.link>
            </h2>

            <p class="line-clamp-2 text-sm text-base-content/70">
              {entry.story.pitch || entry.story.summary}
            </p>

            <.genre_chips genres={entry.story.genres} />

            <dl class="mt-auto grid grid-cols-4 gap-2 border-t border-base-content/10 pt-3 text-xs">
              <div class="flex flex-col gap-0.5">
                <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Score</dt>
                <dd id={"gdr-score-#{entry.id}"}><.score score={entry.score} /></dd>
              </div>
              <div class="flex flex-col gap-0.5">
                <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Members</dt>
                <dd id={"gdr-members-#{entry.id}"} class="font-mono font-bold">{entry.members}</dd>
              </div>
              <div class="flex flex-col gap-0.5">
                <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Online</dt>
                <dd
                  id={"gdr-online-#{entry.id}"}
                  class="inline-flex items-center gap-1 font-mono font-bold"
                >
                  <span class={[
                    "size-2 rounded-full",
                    if(entry.online > 0, do: "bg-success animate-pulse", else: "bg-base-content/20")
                  ]} />
                  {entry.online}
                </dd>
              </div>
              <div class="flex flex-col gap-0.5">
                <dt class="text-[0.65rem] uppercase tracking-wider text-base-content/50">Votes</dt>
                <dd id={"gdr-votes-#{entry.id}"} class="font-mono font-bold">{entry.votes}</dd>
              </div>
            </dl>

            <div class="flex items-center justify-between gap-3 text-xs text-base-content/60">
              <div class="min-w-0">
                <p class="truncate uppercase tracking-wider text-secondary">
                  GM {(entry.story.owner && entry.story.owner.username) || "Platform"}
                </p>
                <p
                  :if={entry.story.masters != []}
                  id={"gdr-masters-#{entry.id}"}
                  class="truncate"
                >
                  Masters: {Enum.map_join(entry.story.masters, ", ", & &1.username)}
                </p>
              </div>
              <.link
                navigate={~p"/g/#{entry.id}"}
                id={"gdr-enter-#{entry.id}"}
                class="relative z-10 inline-flex shrink-0 items-center gap-1 rounded-lg border border-primary/40 px-3 py-1.5 font-bold uppercase tracking-wider text-primary transition hover:bg-primary hover:text-primary-content"
              >
                Enter <.icon name="hero-arrow-right" class="size-3.5" />
              </.link>
            </div>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
