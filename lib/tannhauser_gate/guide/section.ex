defmodule TannhauserGate.Guide.Section do
  @moduledoc "A section of a GDR guide, holding ordered pages."
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Guide.Page
  alias TannhauserGate.Stories.Story

  schema "guide_sections" do
    field :title, :string
    field :position, :integer, default: 0

    belongs_to :story, Story
    has_many :pages, Page, preload_order: [asc: :position, asc: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:title, :position])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
  end
end
