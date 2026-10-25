defmodule TannhauserGateWeb.GameComponents do
  @moduledoc """
  Components specific to Tannhauser Gate: branding, avatars and the
  navigation drawer.
  """
  use Phoenix.Component
  use Gettext, backend: TannhauserGateWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: TannhauserGateWeb.Endpoint,
    router: TannhauserGateWeb.Router,
    statics: TannhauserGateWeb.static_paths()

  import TannhauserGateWeb.CoreComponents, only: [icon: 1]

  @doc "The logo and the site name."
  attr :class, :string, default: nil
  attr :size, :integer, default: 40

  def brand(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-3", @class]}>
      <img src={~p"/images/logo.svg"} width={@size} height={@size} alt="" />
      <span class="font-display text-lg font-bold uppercase tracking-[0.25em] phosphor-text">
        Tannhauser Gate
      </span>
    </span>
    """
  end

  @doc "A character avatar, falling back to the character's initial."
  attr :character, :map, required: true
  attr :class, :string, default: "h-10 w-10"

  def avatar(assigns) do
    ~H"""
    <img
      :if={@character.avatar_path}
      src={@character.avatar_path}
      alt={dgettext("player", "Avatar of %{name}", name: @character.name)}
      class={["rounded-full object-cover ring-2 ring-mint/60", @class]}
    />
    <span
      :if={!@character.avatar_path}
      class={[
        "inline-flex items-center justify-center rounded-full bg-ink font-bold uppercase text-phosphor ring-2 ring-phosphor/50",
        @class
      ]}
      aria-label={dgettext("player", "Avatar of %{name}", name: @character.name)}
    >
      {String.first(@character.name || "?")}
    </span>
    """
  end

  @doc "A navigation link in the drawer."
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :current_path, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def nav_link(assigns) do
    assigns = assign(assigns, :active, active?(assigns.current_path, assigns.navigate))

    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-semibold uppercase tracking-wider transition",
        @active && "bg-phosphor/15 text-phosphor shadow-phosphor",
        !@active && "text-fog-300 hover:bg-mint/10 hover:text-mint"
      ]}
      {@rest}
    >
      <.icon name={@icon} class="h-5 w-5" /> {render_slot(@inner_block)}
    </.link>
    """
  end

  defp active?(nil, _), do: false
  defp active?(path, "/admin"), do: String.starts_with?(path, "/admin")

  defp active?(path, "/map"),
    do:
      path == "/map" or String.starts_with?(path, "/rooms") or
        String.starts_with?(path, "/stories")

  defp active?(path, target), do: path == target or String.starts_with?(path, target <> "/")

  @doc "Formats a timestamp for chat and forum entries."
  def format_time(nil), do: ""
  def format_time(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  def format_local_date(date, format) do
    Calendar.strftime(date, format,
      month_names: &month_name/1,
      abbreviated_month_names: &abbreviated_month_name/1
    )
  end

  defp month_name(1), do: dgettext("player", "January")
  defp month_name(2), do: dgettext("player", "February")
  defp month_name(3), do: dgettext("player", "March")
  defp month_name(4), do: dgettext("player", "April")
  defp month_name(5), do: dgettext("player", "May")
  defp month_name(6), do: dgettext("player", "June")
  defp month_name(7), do: dgettext("player", "July")
  defp month_name(8), do: dgettext("player", "August")
  defp month_name(9), do: dgettext("player", "September")
  defp month_name(10), do: dgettext("player", "October")
  defp month_name(11), do: dgettext("player", "November")
  defp month_name(12), do: dgettext("player", "December")

  defp abbreviated_month_name(1), do: dgettext("player", "Jan")
  defp abbreviated_month_name(2), do: dgettext("player", "Feb")
  defp abbreviated_month_name(3), do: dgettext("player", "Mar")
  defp abbreviated_month_name(4), do: dgettext("player", "Apr")
  defp abbreviated_month_name(5), do: dgettext("player", "May")
  defp abbreviated_month_name(6), do: dgettext("player", "Jun")
  defp abbreviated_month_name(7), do: dgettext("player", "Jul")
  defp abbreviated_month_name(8), do: dgettext("player", "Aug")
  defp abbreviated_month_name(9), do: dgettext("player", "Sep")
  defp abbreviated_month_name(10), do: dgettext("player", "Oct")
  defp abbreviated_month_name(11), do: dgettext("player", "Nov")
  defp abbreviated_month_name(12), do: dgettext("player", "Dec")
end
