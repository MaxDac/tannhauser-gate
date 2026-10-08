defmodule TannhauserGate.Characters.Character do
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  schema "characters" do
    field :name, :string
    field :description, :string
    field :background, :string
    field :avatar_path, :string

    belongs_to :user, User
    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(character, attrs) do
    character
    |> cast(attrs, [:name, :description, :background, :story_id])
    |> validate_required([:name, :story_id])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_length(:background, max: 20_000)
    |> foreign_key_constraint(:story_id)
  end

  @doc """
  Sets the avatar path. Kept separate from `changeset/2` so the path can
  never be supplied by user-submitted params.
  """
  def avatar_changeset(changeset_or_character, avatar_path) do
    change(changeset_or_character, avatar_path: avatar_path)
  end
end
