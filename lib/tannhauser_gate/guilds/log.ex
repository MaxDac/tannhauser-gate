defmodule TannhauserGate.Guilds.Log do
  @moduledoc """
  An entry of a guild's membership log: who (`user`) did what (`action`) to
  which character, with the rank involved when relevant.
  """
  use Ecto.Schema

  @actions ~w(request invite join decline reject cancel leave expel rank)

  def actions, do: @actions

  schema "guild_logs" do
    field :action, :string
    field :rank_name, :string

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :guild, TannhauserGate.Guilds.Guild
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :user, TannhauserGate.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
