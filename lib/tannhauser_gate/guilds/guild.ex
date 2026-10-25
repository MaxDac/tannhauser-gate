defmodule TannhauserGate.Guilds.Guild do
  @moduledoc """
  A guild or faction of a GDR: a name, a Markdown description, an optional
  emblem image and its ranks (`TannhauserGate.Guilds.Rank`).

    * `secret`: the guild and its members are hidden from everyone but its
      members (and the characters it invited or that asked to join) and the
      masters;
    * `open_join`: characters may ask to join; otherwise the guild recruits
      by invitation only.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "guilds" do
    field :name, :string
    field :description, :string
    field :emblem_path, :string
    field :secret, :boolean, default: false
    field :open_join, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :story, TannhauserGate.Stories.Story
    has_many :ranks, TannhauserGate.Guilds.Rank, preload_order: [asc: :position, asc: :id]
    has_many :memberships, TannhauserGate.Guilds.Membership

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(guild, attrs) do
    guild
    |> cast(attrs, [:name, :description, :secret, :open_join, :position])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 20_000)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> unique_constraint(:name, name: :guilds_story_id_name_index)
  end

  def emblem_changeset(guild_or_changeset, path),
    do: change(guild_or_changeset, emblem_path: path)
end
