defmodule TannhauserGate.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.Location

  schema "messages" do
    field :body, :string

    belongs_to :location, Location
    belongs_to :character, Character
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body, :location_id, :character_id, :user_id])
    |> validate_length(:body, max: 4_000)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:character_id)
  end
end
