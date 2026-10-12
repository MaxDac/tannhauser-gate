defmodule TannhauserGate.Stories.LastLocation do
  @moduledoc """
  The last chat room a user visited in a GDR, behind the "Return to chat"
  control of the GDR navigation. One row per user and story.
  """
  use Ecto.Schema

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.{Location, Story}

  schema "user_story_locations" do
    belongs_to :user, User
    belongs_to :story, Story
    belongs_to :location, Location

    timestamps(type: :utc_datetime)
  end
end
