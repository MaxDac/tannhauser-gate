defmodule TannhauserGate.Characters.Character do
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Bank.Job
  alias TannhauserGate.Sheet.Trait
  alias TannhauserGate.Stories.Story

  schema "characters" do
    field :name, :string
    field :description, :string
    field :background, :string
    field :avatar_path, :string
    field :balance, :integer, default: 0
    field :last_paid_at, :utc_datetime

    belongs_to :user, User
    belongs_to :story, Story
    belongs_to :job, Job
    has_many :traits, Trait

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(character, attrs) do
    # A character can never move to another GDR once created.
    fields =
      if character.id,
        do: [:name, :description, :background],
        else: [:name, :description, :background, :story_id]

    character
    |> cast(attrs, fields)
    |> validate_required([:name, :story_id])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_length(:background, max: 20_000)
    |> foreign_key_constraint(:story_id)
    |> unique_constraint(:story_id,
      name: :characters_user_id_story_id_index,
      message: "you already have a character in this GDR"
    )
  end

  @doc """
  Sets the avatar path. Kept separate from `changeset/2` so the path can
  never be supplied by user-submitted params.
  """
  def avatar_changeset(changeset_or_character, avatar_path) do
    change(changeset_or_character, avatar_path: avatar_path)
  end
end
