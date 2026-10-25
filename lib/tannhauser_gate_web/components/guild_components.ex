defmodule TannhauserGateWeb.GuildComponents do
  @moduledoc "Components for the guilds module."
  use Phoenix.Component
  use Gettext, backend: TannhauserGateWeb.Gettext

  @doc "A guild emblem, or its initial on a tinted tile when it has none."
  attr :guild, :map, required: true
  attr :class, :any, default: "size-10"
  attr :id, :string, default: nil

  def guild_emblem(assigns) do
    ~H"""
    <img
      :if={@guild.emblem_path}
      id={@id}
      src={@guild.emblem_path}
      alt={dgettext("player", "Emblem of %{name}", name: @guild.name)}
      class={["shrink-0 rounded-lg object-cover ring-1 ring-primary/30", @class]}
    />
    <span
      :if={!@guild.emblem_path}
      id={@id}
      aria-hidden="true"
      class={[
        "flex shrink-0 items-center justify-center rounded-lg bg-primary/10 font-bold uppercase text-primary ring-1 ring-primary/30",
        @class
      ]}
    >
      {String.first(@guild.name)}
    </span>
    """
  end
end
