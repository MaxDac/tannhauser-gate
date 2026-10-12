defmodule TannhauserGate.Trackers.CharacterTracker do
  @moduledoc """
  The state of a tracker for one character: the current `value` (for simple
  trackers) and the `damage` by type (for trackers with damage types).
  Rows are created lazily the first time a tracker changes.
  """

  use Ecto.Schema

  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Trackers.Tracker

  schema "character_trackers" do
    field :value, :integer
    field :damage, :map, default: %{}

    belongs_to :character, Character
    belongs_to :tracker, Tracker

    timestamps(type: :utc_datetime)
  end
end
