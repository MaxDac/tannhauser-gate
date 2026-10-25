defmodule TannhauserGateWeb.GmNav do
  @moduledoc """
  The GM config header and tab navigation, shared by `TannhauserGateWeb.GmLive`
  (whose core tabs are patched) and the GM pages living in their own
  LiveViews (guide, zones, periodic actions), which are navigated to.
  """
  use TannhauserGateWeb, :html

  @tabs [
    {"general", "General", :core},
    {"modules", "Modules", :core},
    {"guide", "Guide", :page},
    {"theme", "Theme", :core},
    {"sheet", "Sheet", :core},
    {"creation", "Creation & XP", :core},
    {"trackers", "Trackers", :core},
    {"states", "States", :core},
    {"jobs", "Jobs", :core},
    {"balances", "Balances", :core},
    {"map", "Map", :core},
    {"zones", "Zones", :page},
    {"actions", "Periodic actions", :page},
    {"chat", "Chat & dice", :core},
    {"forum", "Forum", :core},
    {"masters", "Masters", :core}
  ]

  # Tabs of optional modules (`TannhauserGate.Modules`), shown only when the
  # module is enabled: {key, label, kind, module}.
  @module_tabs []

  @doc "The keys of the tabs rendered by `GmLive` itself."
  def core_tabs,
    do: for({key, _, :core} <- @tabs, do: key) ++ for({key, _, :core, _} <- @module_tabs, do: key)

  @doc "The tabs shown for the story: the core ones plus those of its enabled modules."
  def visible_tabs(story) do
    @tabs ++
      for {key, label, kind, module} <- @module_tabs,
          TannhauserGate.Stories.module_enabled?(story, module),
          do: {key, label, kind}
  end

  attr :story, :map, required: true

  def gm_header(assigns) do
    ~H"""
    <.header>
      GM dashboard
      <:subtitle>
        Shape {@story.name}: guide, look, sheet, economy, map, zones and masters.
      </:subtitle>
      <:actions>
        <.button id="gm-master-tools-link" navigate={~p"/g/#{@story}/master"}>
          <.icon name="hero-megaphone" class="size-4" /> Master tools
        </.button>
      </:actions>
    </.header>
    """
  end

  attr :story, :map, required: true
  attr :tab, :string, required: true

  def gm_tabs(assigns) do
    assigns =
      assign(assigns,
        tabs: visible_tabs(assigns.story),
        in_core?: assigns.tab in core_tabs()
      )

    ~H"""
    <nav
      id="gm-tabs"
      class="mt-6 flex flex-wrap gap-2 border-b border-secondary/20 pb-3"
      aria-label="Dashboard"
    >
      <.link
        :for={{key, label, kind} <- @tabs}
        id={"gm-tab-#{key}"}
        patch={if(kind == :core and @in_core?, do: ~p"/g/#{@story}/gm/#{key}")}
        navigate={if(kind == :page or not @in_core?, do: ~p"/g/#{@story}/gm/#{key}")}
        class={[
          "rounded-md px-3 py-1.5 text-xs font-bold uppercase tracking-wider transition-colors",
          if(@tab == key,
            do: "bg-primary/20 text-primary",
            else: "text-base-content/60 hover:text-secondary"
          )
        ]}
      >
        {label}
      </.link>
    </nav>
    """
  end
end
