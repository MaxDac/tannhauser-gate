defmodule TannhauserGate.Esiti.Message do
  @moduledoc """
  A message in the thread of an esito: written by the requester (as its
  character) or by a master (as "The masters" or signed with their name).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "esito_messages" do
    field :from_masters, :boolean, default: false
    field :author_name, :string
    field :body, :string

    belongs_to :esito, TannhauserGate.Esiti.Esito
    belongs_to :user, TannhauserGate.Accounts.User
    belongs_to :character, TannhauserGate.Characters.Character

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, max: 10_000)
  end
end
