defmodule TannhauserGate.Stories.StoryMaster do
  @moduledoc """
  A master (narrator) of a GDR. Masters run the game (chat, characters,
  moderation) but cannot change the GDR configuration, which belongs to its
  admin (the story owner).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  schema "story_masters" do
    belongs_to :story, Story
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(story_master) do
    story_master
    |> change()
    |> foreign_key_constraint(:story_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:story_id, :user_id], message: "is already a master of this GDR")
  end
end
