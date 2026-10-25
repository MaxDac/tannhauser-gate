defmodule TannhauserGate.Characters.Character do
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Bank.Job
  alias TannhauserGate.Characters.State
  alias TannhauserGate.Sheet.Trait
  alias TannhauserGate.Stories.Story

  @approval_statuses ~w(draft submitted approved rejected)

  schema "characters" do
    field :name, :string
    field :description, :string
    field :background, :string
    field :avatar_path, :string
    field :balance, :integer, default: 0
    field :last_paid_at, :utc_datetime

    # Approval flow: draft -> submitted -> approved | rejected.
    field :approval_status, :string, default: "draft"
    field :review_notes, :string
    field :reviewed_at, :utc_datetime

    # NPCs belong to the GDR: `user` is just the master who created them.
    field :is_npc, :boolean, default: false

    # Owner-editable notes and off-game info; master notes are hidden from the owner.
    field :player_notes, :string
    field :off_game_info, :string
    field :master_notes, :string

    belongs_to :user, User
    belongs_to :story, Story
    belongs_to :job, Job
    belongs_to :state, State
    belongs_to :reviewed_by, User
    has_many :traits, Trait

    timestamps(type: :utc_datetime)
  end

  def approval_statuses, do: @approval_statuses

  @owner_fields [:name, :description, :background, :player_notes, :off_game_info]

  @doc """
  The changeset used by owners. Masters pass `master?: true` to also edit the
  master-only notes.
  """
  def changeset(character, attrs, opts \\ []) do
    # A character can never move to another GDR once created.
    fields = if character.id, do: @owner_fields, else: [:story_id | @owner_fields]
    fields = if opts[:master?], do: [:master_notes | fields], else: fields

    character
    |> cast(attrs, fields)
    |> validate_required([:name, :story_id])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_length(:background, max: 20_000)
    |> validate_length(:player_notes, max: 20_000)
    |> validate_length(:off_game_info, max: 5_000)
    |> validate_length(:master_notes, max: 20_000)
    |> foreign_key_constraint(:story_id)
  end

  @doc "Moves the character to another approval status (never from user params)."
  def review_changeset(character, status, attrs) when status in @approval_statuses do
    character
    |> change(approval_status: status)
    |> change(attrs)
    |> validate_length(:review_notes, max: 5_000)
  end

  @doc """
  Sets the avatar path. Kept separate from `changeset/2` so the path can
  never be supplied by user-submitted params.
  """
  def avatar_changeset(changeset_or_character, avatar_path) do
    change(changeset_or_character, avatar_path: avatar_path)
  end
end
