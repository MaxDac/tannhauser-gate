defmodule TannhauserGateWeb.CharacterComponents do
  @moduledoc """
  Small components shared wherever a character is shown.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TannhauserGateWeb.Endpoint,
    router: TannhauserGateWeb.Router,
    statics: TannhauserGateWeb.static_paths()

  import TannhauserGateWeb.CoreComponents, only: [icon: 1]

  @doc """
  A character name that opens a small menu of quick links: view the sheet,
  send a letter (the mailbox compose page with the character prefilled) and,
  when given, go to the location the character is in.

  The trigger is the character name, or the inner block when given. Link IDs
  are `"<id>-sheet"`, `"<id>-message"` and `"<id>-location"`.

  ## Examples

      <.character_quick_links id="online-1-links" story={@current_story} character={character} />
  """
  attr :id, :string, required: true
  attr :story, :any, required: true, doc: "the GDR (story) the character belongs to"
  attr :character, :map, required: true, doc: "a map with the character `id` and `name`"

  attr :location, :map,
    default: nil,
    doc: "the `%{id, name}` location the character is in, when the viewer may follow them"

  attr :status, :string,
    default: nil,
    doc: "the presence status of the character's player when online (shown in the menu)"

  attr :class, :any, default: nil, doc: "classes for the trigger"
  attr :align, :string, default: "start", values: ~w(start end)
  slot :inner_block

  def character_quick_links(assigns) do
    ~H"""
    <div
      id={@id}
      class={["dropdown character-quick-links", @align == "end" && "dropdown-end"]}
    >
      <div
        id={"#{@id}-trigger"}
        tabindex="0"
        role="button"
        aria-haspopup="menu"
        aria-label={"Quick links for #{@character.name}"}
        class={["cursor-pointer hover:underline", @class]}
      >
        <%= if @inner_block != [] do %>
          {render_slot(@inner_block)}
        <% else %>
          {@character.name}
        <% end %>
      </div>
      <ul
        tabindex="0"
        role="menu"
        class="dropdown-content menu menu-sm z-50 mt-1 w-52 rounded-box border border-secondary/30 bg-base-200 p-1 text-xs font-normal normal-case tracking-normal shadow-phosphor"
      >
        <li :if={@status} id={"#{@id}-status"} role="none" class="menu-title px-3 py-1.5">
          <span class="flex items-center gap-2 normal-case tracking-normal">
            <.presence_dot status={@status} /> {presence_label(@status)}
          </span>
        </li>
        <li role="none">
          <.link
            id={"#{@id}-sheet"}
            role="menuitem"
            navigate={~p"/g/#{@story}/characters/#{@character.id}"}
          >
            <.icon name="hero-identification-micro" class="size-4" /> View sheet
          </.link>
        </li>
        <li role="none">
          <.link
            id={"#{@id}-message"}
            role="menuitem"
            navigate={~p"/g/#{@story}/mail/new?#{[to: @character.id]}"}
          >
            <.icon name="hero-envelope-micro" class="size-4" /> Send message
          </.link>
        </li>
        <li :if={@location} role="none">
          <.link
            id={"#{@id}-location"}
            role="menuitem"
            navigate={~p"/g/#{@story}/rooms/#{@location.id}"}
          >
            <.icon name="hero-map-pin-micro" class="size-4" />
            <span class="truncate">Go to {@location.name}</span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  @doc "A small colored dot showing a presence status (see `presence_label/1`)."
  attr :status, :string, required: true
  attr :id, :string, default: nil

  def presence_dot(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "presence-dot inline-block size-2 shrink-0 rounded-full transition-colors",
        "presence-#{@status}",
        presence_color(@status)
      ]}
      title={presence_label(@status)}
      aria-label={presence_label(@status)}
    ></span>
    """
  end

  @doc "Human readable label of a presence status."
  def presence_label("available"), do: "Available"
  def presence_label("busy"), do: "Busy"
  def presence_label("away"), do: "Away"
  def presence_label("looking_for_play"), do: "Looking for play"
  def presence_label(_), do: "Available"

  defp presence_color("busy"), do: "bg-error shadow-[0_0_6px] shadow-error/70"
  defp presence_color("away"), do: "bg-warning/80"

  defp presence_color("looking_for_play"),
    do: "bg-info shadow-[0_0_6px] shadow-info/70 animate-pulse"

  defp presence_color(_), do: "bg-mint shadow-[0_0_6px] shadow-mint/70"
end
