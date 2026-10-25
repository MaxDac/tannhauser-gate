defmodule TannhauserGate.Diary.Entry do
  @moduledoc """
  An in-character diary entry of a character: a title, a Markdown body, an
  optional in-game date label (free text until the game calendar fills it)
  and a visibility:

    * `public` - everyone in the GDR;
    * `masters` - the owner and the masters (shared with the narration team);
    * `private` - the owner only; the masters (GDR admin and platform admins
      included) can still read it for moderation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @visibilities ~w(public masters private)

  def visibilities, do: @visibilities

  schema "diary_entries" do
    field :title, :string
    field :body, :string
    field :game_date_label, :string
    field :visibility, :string, default: "public"

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :user, TannhauserGate.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:title, :body, :game_date_label, :visibility])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :body, :visibility])
    |> validate_length(:title, max: 120)
    |> validate_length(:body, max: 20_000)
    |> validate_length(:game_date_label, max: 80)
    |> validate_inclusion(:visibility, @visibilities)
  end
end
