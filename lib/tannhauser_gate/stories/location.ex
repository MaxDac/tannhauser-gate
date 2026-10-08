defmodule TannhauserGate.Stories.Location do
  @moduledoc """
  A location (chat room) inside a story. Its `area` is an SVG polygon
  `points` string (e.g. `"10,10 120,10 120,90 10,90"`) in map coordinates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Story

  @points_format ~r/^\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?(\s+-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?){2,}\s*$/

  schema "locations" do
    field :name, :string
    field :description, :string
    field :area, :string
    field :color, :string, default: "#4ae08a"

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :description, :area, :color])
    |> validate_required([:name, :area, :color])
    |> validate_length(:name, max: 120)
    |> validate_format(:area, @points_format,
      message: "must be a list of at least 3 x,y points separated by spaces"
    )
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a hex color like #4ae08a")
    |> foreign_key_constraint(:story_id)
    |> unique_constraint([:story_id, :name])
  end

  @doc """
  Parses the polygon points into a list of `{x, y}` float tuples.
  """
  def points(%__MODULE__{area: area}), do: points(area)

  def points(area) when is_binary(area) do
    area
    |> String.split(~r/\s+/, trim: true)
    |> Enum.flat_map(fn pair ->
      case String.split(pair, ",") do
        [x, y] -> [{parse(x), parse(y)}]
        _ -> []
      end
    end)
  end

  def points(_), do: []

  @doc """
  The average point of the polygon, used to place labels on the map.
  """
  def centroid(location) do
    case points(location) do
      [] ->
        {0.0, 0.0}

      pts ->
        n = length(pts)
        {sx, sy} = Enum.reduce(pts, {0.0, 0.0}, fn {x, y}, {ax, ay} -> {ax + x, ay + y} end)
        {Float.round(sx / n, 1), Float.round(sy / n, 1)}
    end
  end

  defp parse(value) do
    case Float.parse(String.trim(value)) do
      {float, _} -> float
      :error -> 0.0
    end
  end
end
