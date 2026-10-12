defmodule TannhauserGate.PeriodicActions.Difficulty do
  @moduledoc "A per-character difficulty for a periodic action, set by the masters."
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Characters.Character
  alias TannhauserGate.PeriodicActions.Action

  schema "periodic_action_difficulties" do
    field :difficulty, :integer

    belongs_to :action, Action
    belongs_to :character, Character

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(difficulty, attrs) do
    difficulty
    |> cast(attrs, [:difficulty])
    |> validate_required([:difficulty])
    |> validate_number(:difficulty, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
