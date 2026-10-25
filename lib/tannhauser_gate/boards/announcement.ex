defmodule TannhauserGate.Boards.Announcement do
  @moduledoc """
  A GDR announcement posted by a master: title, Markdown body, pinned flag
  and an optional expiry, after which it is no longer shown to the players.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "announcements" do
    field :title, :string
    field :body, :string
    field :pinned, :boolean, default: false
    field :expires_at, :utc_datetime

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :user, TannhauserGate.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(announcement, attrs) do
    announcement
    |> cast(attrs, [:title, :body, :pinned, :expires_at])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :body])
    |> validate_length(:title, max: 120)
    |> validate_length(:body, max: 20_000)
  end

  @doc "Whether the announcement expired at `now`."
  def expired?(%__MODULE__{expires_at: nil}, _now), do: false
  def expired?(%__MODULE__{expires_at: at}, now), do: DateTime.compare(at, now) != :gt
end
