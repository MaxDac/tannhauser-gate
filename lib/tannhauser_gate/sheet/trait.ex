defmodule TannhauserGate.Sheet.Trait do
  use Ecto.Schema

  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Sheet.Item

  schema "character_traits" do
    field :value, :integer, default: 0

    belongs_to :character, Character
    belongs_to :sheet_item, Item
  end
end
