defmodule TannhauserGate.Characters.ActiveCharacter do
  @moduledoc """
  The character a user is currently playing in a GDR (when the GDR allows more
  than one character per user). One row per user and story; see
  `TannhauserGate.Characters.active_character/2`.
  """
  use Ecto.Schema

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.Story

  schema "user_active_characters" do
    belongs_to :user, User
    belongs_to :story, Story
    belongs_to :character, Character

    timestamps(type: :utc_datetime)
  end
end
