defmodule TannhauserGate.Stories.PresenceStatus do
  @moduledoc """
  The availability a user shows to the other players of a GDR (online list
  and character quick links): available, busy, away or looking for play. One
  row per user and story; users without a row are available.
  """
  use Ecto.Schema

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  @statuses ~w(available busy away looking_for_play)

  schema "presence_statuses" do
    field :status, :string, default: "available"

    belongs_to :user, User
    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
end
