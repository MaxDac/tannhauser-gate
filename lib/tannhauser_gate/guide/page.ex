defmodule TannhauserGate.Guide.Page do
  @moduledoc "A Markdown page of a GDR guide section."
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Guide.Section

  schema "guide_pages" do
    field :title, :string
    field :body, :string, default: ""
    field :position, :integer, default: 0

    belongs_to :section, Section

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :body, :position, :section_id])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :section_id])
    |> validate_length(:title, max: 120)
    |> validate_length(:body, max: 100_000)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> foreign_key_constraint(:section_id)
  end
end
