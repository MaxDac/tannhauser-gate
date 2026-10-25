defmodule TannhauserGate.Guilds.Membership do
  @moduledoc """
  A character's membership of a guild: `"requested"` (the character asked to
  join), `"invited"` (the guild invited it) or `"active"`. Active members hold
  a rank and are paid its salary; `last_paid_at` is the salary clock.
  """
  use Ecto.Schema

  @statuses ~w(requested invited active)

  def statuses, do: @statuses

  schema "guild_memberships" do
    field :status, :string
    field :last_paid_at, :utc_datetime

    belongs_to :guild, TannhauserGate.Guilds.Guild
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :rank, TannhauserGate.Guilds.Rank

    timestamps(type: :utc_datetime)
  end
end
