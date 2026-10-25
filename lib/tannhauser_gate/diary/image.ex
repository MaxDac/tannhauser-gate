defmodule TannhauserGate.Diary.Image do
  @moduledoc "A picture of a character's gallery, stored through `TannhauserGate.Storage`."
  use Ecto.Schema
  import Ecto.Changeset

  schema "character_images" do
    field :path, :string
    field :caption, :string

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :character, TannhauserGate.Characters.Character

    timestamps(type: :utc_datetime)
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [:caption])
    |> update_change(:caption, &String.trim/1)
    |> validate_length(:caption, max: 140)
  end
end
