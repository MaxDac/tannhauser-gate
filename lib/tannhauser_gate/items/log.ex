defmodule TannhauserGate.Items.Log do
  @moduledoc """
  An entry of the item log: who (`user`) did what (`action`) with how many
  units of an item on a character (and, when given, to `target_character`).
  The item name is kept in case the item is deleted from the catalog.
  """
  use Ecto.Schema

  @actions ~w(grant remove give buy use equip unequip)

  def actions, do: @actions

  schema "item_logs" do
    field :item_name, :string
    field :quantity, :integer
    field :action, :string
    field :note, :string

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :target_character, TannhauserGate.Characters.Character
    belongs_to :item, TannhauserGate.Items.Item
    belongs_to :user, TannhauserGate.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
