defmodule TannhauserGate.Chat.Message do
  @moduledoc """
  A chat entry posted in a location. Its `kind` decides how it is rendered:

    * `"speech"` - in-character speech of a playable character (default);
    * `"ooc"` - an out-of-character (OFF) note of a character owner;
    * `"narration"` - master narration, posted as the Narrator (no character);
    * `"status"` - a master update of the room status (no character);
    * `"dice"` - a dice roll, whose structured result is in `data`;
    * `"whisper"` - in-character speech to one character
      (`recipient_character`), visible only to the sender, the recipient's
      owner and the masters (chat roleplay module).

  In-character entries (`"speech"`, `"whisper"`) may carry a short action
  `tag` (e.g. "at the bar") when the chat roleplay module is on.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.Location

  @kinds ~w(speech ooc narration status dice whisper)
  @character_kinds ~w(speech ooc dice whisper)
  @in_character_kinds ~w(speech whisper)
  @tag_max 40

  schema "messages" do
    field :body, :string
    field :kind, :string, default: "speech"
    field :data, :map
    field :tag, :string

    belongs_to :location, Location
    belongs_to :character, Character
    belongs_to :user, User
    belongs_to :recipient_character, Character

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc "Whether entries of this kind are posted by a character."
  def character_kind?(kind), do: kind in @character_kinds

  @doc "Whether entries of this kind are in-character text (speech or whisper)."
  def in_character_kind?(kind), do: kind in @in_character_kinds

  @doc "The maximum length of an action tag."
  def tag_max, do: @tag_max

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :tag])
    |> update_change(:body, &String.trim/1)
    |> update_change(:tag, &blank_to_nil/1)
    |> validate_required([:body, :location_id, :user_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_character()
    |> validate_length(:body, max: 4_000)
    |> validate_length(:tag, max: @tag_max)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:recipient_character_id)
  end

  @doc """
  Validates the GDR length limits (`min`/`max` characters, nil for none) of
  the body of an in-character entry.
  """
  def validate_limits(changeset, min, max) do
    opts = Enum.reject([min: min, max: max], fn {_, v} -> is_nil(v) or v <= 0 end)

    if opts != [] and in_character_kind?(get_field(changeset, :kind)),
      do: validate_length(changeset, :body, opts),
      else: changeset
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(tag) do
    case String.trim(tag) do
      "" -> nil
      tag -> tag
    end
  end

  defp validate_character(changeset) do
    case get_field(changeset, :kind) do
      "whisper" ->
        validate_required(changeset, [:character_id, :recipient_character_id])

      kind ->
        if character_kind?(kind),
          do: validate_required(changeset, [:character_id]),
          else: changeset
    end
  end
end
