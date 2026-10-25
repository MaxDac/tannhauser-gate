defmodule TannhauserGate.Directory.Vote do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A user's vote for a GDR: one per user, GDR and calendar month (UTC),
  `month` being the first day of the month.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  schema "gdr_votes" do
    field :month, :date

    belongs_to :story, Story
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(vote) do
    vote
    |> change()
    |> unique_constraint([:story_id, :user_id, :month],
      message: dgettext_noop("errors", "already voted this month")
    )
  end
end
