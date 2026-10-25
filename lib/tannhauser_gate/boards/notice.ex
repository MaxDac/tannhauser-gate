defmodule TannhauserGate.Boards.Notice do
  @moduledoc """
  A short in-character notice pinned on a board by a character (Markdown),
  with an optional expiry after which it is no longer shown.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "board_notices" do
    field :title, :string
    field :body, :string
    field :expires_at, :utc_datetime

    belongs_to :board, TannhauserGate.Boards.Board
    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :user, TannhauserGate.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(notice, attrs) do
    notice
    |> cast(attrs, [:title, :body, :expires_at])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:title, max: 80)
    |> validate_length(:body, max: 1_000)
    |> validate_change(:expires_at, fn :expires_at, at ->
      if DateTime.compare(at, DateTime.utc_now()) == :gt,
        do: [],
        else: [expires_at: "must be in the future"]
    end)
  end
end
