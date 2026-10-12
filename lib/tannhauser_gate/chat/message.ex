defmodule TannhauserGate.Chat.Message do
  @moduledoc """
  A chat entry posted in a location. Its `kind` decides how it is rendered:

    * `"speech"` - in-character speech of a playable character (default);
    * `"ooc"` - an out-of-character (OFF) note of a character owner;
    * `"narration"` - master narration, posted as the Narrator (no character);
    * `"status"` - a master update of the room status (no character);
    * `"dice"` - a dice roll, whose structured result is in `data`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.Location

  @kinds ~w(speech ooc narration status dice)
  @character_kinds ~w(speech ooc dice)

  schema "messages" do
    field :body, :string
    field :kind, :string, default: "speech"
    field :data, :map

    belongs_to :location, Location
    belongs_to :character, Character
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc "Whether entries of this kind are posted by a character."
  def character_kind?(kind), do: kind in @character_kinds

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body, :location_id, :user_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_character()
    |> validate_length(:body, max: 4_000)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:character_id)
  end

  defp validate_character(changeset) do
    if character_kind?(get_field(changeset, :kind)),
      do: validate_required(changeset, [:character_id]),
      else: changeset
  end
end
