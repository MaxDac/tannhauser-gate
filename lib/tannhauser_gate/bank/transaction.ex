defmodule TannhauserGate.Bank.Transaction do
  use Ecto.Schema

  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.Story

  schema "bank_transactions" do
    field :amount, :integer
    field :kind, :string
    field :note, :string

    belongs_to :story, Story
    belongs_to :from_character, Character
    belongs_to :to_character, Character

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
