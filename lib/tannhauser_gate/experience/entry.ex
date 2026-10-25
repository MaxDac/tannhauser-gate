defmodule TannhauserGate.Experience.Entry do
  @moduledoc """
  An entry of a character's XP log: an `"award"` by a master (positive, or
  negative as a correction) or a `"spend"` by the owner to raise a sheet item
  (`amount` is the positive cost).

  `source` is `"manual"` (masters and spends) or `"auto"` (awarded by the
  automatic XP module for chat activity, without an author).
  """

  use Ecto.Schema

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Sheet.Item
  alias TannhauserGate.Stories.Story

  schema "xp_entries" do
    field :kind, :string
    field :amount, :integer
    field :reason, :string
    field :item_name, :string
    field :from_value, :integer
    field :to_value, :integer
    field :source, :string, default: "manual"

    belongs_to :story, Story
    belongs_to :character, Character
    belongs_to :author, User
    belongs_to :sheet_item, Item

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
