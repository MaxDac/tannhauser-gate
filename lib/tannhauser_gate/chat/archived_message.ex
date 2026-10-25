defmodule TannhauserGate.Chat.ArchivedMessage do
  @moduledoc """
  A chat entry moved out of the live chat by `TannhauserGate.Chat.Archiver`
  once older than the GDR archive age. `speaker_name` keeps the name of the
  character (or "Narrator") at archival time, `recipient_name` the one of the
  recipient of a whisper.
  """
  use Ecto.Schema

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.Location

  schema "archived_messages" do
    field :body, :string
    field :kind, :string, default: "speech"
    field :data, :map
    field :speaker_name, :string
    field :tag, :string
    field :recipient_name, :string
    field :inserted_at, :utc_datetime
    field :archived_at, :utc_datetime

    belongs_to :location, Location
    belongs_to :character, Character
    belongs_to :user, User
    belongs_to :recipient_character, Character
  end
end
