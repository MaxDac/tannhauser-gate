defmodule TannhauserGate.Stories.Story do
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Location

  schema "stories" do
    field :name, :string
    field :summary, :string
    field :world_background, :string
    field :customs, :string
    field :map_svg, :string
    field :map_width, :integer, default: 1000
    field :map_height, :integer, default: 700
    field :is_default, :boolean, default: false

    has_many :locations, Location, preload_order: [asc: :name]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(story, attrs) do
    story
    |> cast(attrs, [
      :name,
      :summary,
      :world_background,
      :customs,
      :map_svg,
      :map_width,
      :map_height,
      :is_default
    ])
    |> validate_required([:name, :map_width, :map_height])
    |> validate_length(:name, max: 120)
    |> validate_number(:map_width, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:map_height, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_map_svg()
    |> unique_constraint(:name)
  end

  # The map artwork is admin-authored SVG markup rendered inline, so reject the
  # obvious script vectors as a defence in depth measure.
  defp validate_map_svg(changeset) do
    validate_change(changeset, :map_svg, fn :map_svg, svg ->
      if svg =~ ~r/<\s*script|<\s*foreignObject|\son[a-z]+\s*=|javascript:/i do
        [map_svg: "must not contain scripts, event handlers or foreignObject"]
      else
        []
      end
    end)
  end
end
