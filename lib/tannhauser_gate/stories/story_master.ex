defmodule TannhauserGate.Stories.StoryMaster do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A master (narrator) of a GDR. Masters run the game (chat, characters,
  moderation) but cannot change the GDR configuration, which belongs to its
  admin (the story owner).

  The permission flags (all on by default) split the master tools: see
  `TannhauserGate.Stories.can?/3`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  @permissions [
    :can_moderate,
    :can_approve_characters,
    :can_award_xp,
    :can_manage_esiti_quests,
    :can_manage_economy,
    :can_manage_world
  ]

  schema "story_masters" do
    belongs_to :story, Story
    belongs_to :user, User

    field :can_moderate, :boolean, default: true
    field :can_approve_characters, :boolean, default: true
    field :can_award_xp, :boolean, default: true
    field :can_manage_esiti_quests, :boolean, default: true
    field :can_manage_economy, :boolean, default: true
    field :can_manage_world, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc "The permission flags, in display order."
  def permissions, do: @permissions

  @doc false
  def changeset(story_master) do
    story_master
    |> change()
    |> foreign_key_constraint(:story_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:story_id, :user_id],
      message: dgettext_noop("errors", "is already a master of this GDR")
    )
  end

  @doc "Changes the permission flags."
  def permissions_changeset(story_master, attrs) do
    cast(story_master, attrs, @permissions)
  end
end
