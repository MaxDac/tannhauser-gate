defmodule TannhauserGate.Items.CharacterItem do
  @moduledoc "A stack of an item in a character's inventory, possibly equipped."
  use Ecto.Schema

  schema "character_items" do
    field :quantity, :integer, default: 1
    field :equipped, :boolean, default: false

    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :item, TannhauserGate.Items.Item

    timestamps(type: :utc_datetime)
  end
end
