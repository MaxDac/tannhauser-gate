defmodule TannhauserGate.Quests.Participant do
  @moduledoc """
  A character taking part in a quest, with its rewards: XP, money and
  optionally an item (items module) with a quantity, plus a note.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "quest_participants" do
    field :xp, :integer, default: 0
    field :money, :integer, default: 0
    field :item_quantity, :integer, default: 0
    field :note, :string

    belongs_to :quest, TannhauserGate.Quests.Quest
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :item, TannhauserGate.Items.Item

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the rewards; the character and item ids are checked by `TannhauserGate.Quests`."
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:xp, :money, :item_quantity, :note])
    |> put_default(:xp)
    |> put_default(:money)
    |> put_default(:item_quantity)
    |> validate_number(:xp, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000)
    |> validate_number(:money, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000)
    |> validate_number(:item_quantity, greater_than_or_equal_to: 0, less_than_or_equal_to: 999)
    |> validate_length(:note, max: 200)
    |> unique_constraint(:character_id,
      name: :quest_participants_quest_id_character_id_index,
      message: "already takes part in this quest"
    )
  end

  defp put_default(changeset, field) do
    if get_field(changeset, field) == nil, do: put_change(changeset, field, 0), else: changeset
  end
end
