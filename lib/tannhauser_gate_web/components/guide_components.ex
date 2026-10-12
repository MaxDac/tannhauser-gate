defmodule TannhauserGateWeb.GuideComponents do
  @moduledoc "Components to render the GDR guide."
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TannhauserGateWeb.Endpoint,
    router: TannhauserGateWeb.Router,
    statics: TannhauserGateWeb.static_paths()

  alias TannhauserGate.Guide

  @doc "Renders Markdown as sanitized HTML."
  attr :id, :string, default: nil
  attr :content, :string, default: ""
  attr :class, :string, default: nil

  def markdown(assigns) do
    ~H"""
    <div id={@id} class={["guide-prose", @class]}>{Phoenix.HTML.raw(Guide.to_html(@content))}</div>
    """
  end

  @doc "The guide table of contents: sections and their page links."
  attr :id, :string, required: true
  attr :story, :map, required: true
  attr :sections, :list, required: true
  attr :current_page_id, :integer, default: nil

  def guide_toc(assigns) do
    ~H"""
    <nav id={@id} class="space-y-4">
      <div :for={section <- @sections} id={"#{@id}-section-#{section.id}"}>
        <h3 class="text-xs font-bold uppercase tracking-[0.2em] text-secondary">{section.title}</h3>
        <ul class="mt-1 space-y-0.5">
          <li :for={page <- section.pages}>
            <.link
              id={"#{@id}-page-#{page.id}"}
              navigate={~p"/g/#{@story}/guide/#{page.id}"}
              class={[
                "block rounded px-2 py-1 text-sm transition-colors hover:bg-base-300/60 hover:text-primary",
                if(page.id == @current_page_id,
                  do: "bg-base-300/60 font-semibold text-primary",
                  else: "text-base-content/80"
                )
              ]}
            >
              {page.title}
            </.link>
          </li>
          <li :if={section.pages == []} class="px-2 text-xs italic text-base-content/50">
            No pages yet.
          </li>
        </ul>
      </div>
    </nav>
    """
  end
end
