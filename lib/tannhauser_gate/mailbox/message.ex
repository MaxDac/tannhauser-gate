defmodule TannhauserGate.Mailbox.Message do
  @moduledoc """
  A message between characters of a GDR. A nil recipient is the shared
  mailbox of the masters; a message `from_masters` was sent by a master on
  behalf of all of them. Each side deletes the message independently.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "mail_messages" do
    field :sender_name, :string
    field :from_masters, :boolean, default: false
    field :subject, :string
    field :body, :string
    field :read_at, :utc_datetime
    field :sender_deleted_at, :utc_datetime
    field :recipient_deleted_at, :utc_datetime
    # Form fields: "masters" or a character id.
    field :sender, :string, virtual: true
    field :recipient, :string, virtual: true

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :sender_user, TannhauserGate.Accounts.User
    belongs_to :sender_character, TannhauserGate.Characters.Character
    belongs_to :recipient_character, TannhauserGate.Characters.Character
    belongs_to :reply_to, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:sender, :recipient, :subject, :body])
    |> update_change(:subject, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:sender, :recipient, :subject, :body])
    |> validate_length(:subject, max: 200)
    |> validate_length(:body, max: 20_000)
  end
end
