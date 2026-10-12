defmodule TannhauserGate.PeriodicActions.Log do
  @moduledoc """
  A performed periodic action. Runs with `counts_for_cooldown: false` were
  cleared by a master cooldown reset.
  """
  use Ecto.Schema

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.PeriodicActions.Action
  alias TannhauserGate.Stories.Location

  schema "periodic_action_logs" do
    field :difficulty, :integer
    field :success, :boolean
    field :summary, :string
    field :effect, :string
    field :result, :map, default: %{}
    field :counts_for_cooldown, :boolean, default: true

    belongs_to :action, Action
    belongs_to :character, Character
    belongs_to :user, User
    belongs_to :location, Location

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
