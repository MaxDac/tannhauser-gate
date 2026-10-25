defmodule TannhauserGate.Stories.Location do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A location (chat room) inside a story. Private locations can only be
  used by masters and by whoever booked them (see `TannhauserGate.Bookings`);
  `status` is the current room status set by the masters. With the guilds
  module, a location restricted to a `guild` is open only to the masters and
  the owners of the guild's active members. It belongs to at most one TannhauserGate.Zones.Zone. Its `area` is an SVG polygon
  `points` string (e.g. `"10,10 120,10 120,90 10,90"`) in map coordinates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Story
  alias TannhauserGate.Zones.Zone

  @points_format ~r/^\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?(\s+-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?){2,}\s*$/

  @type t :: %__MODULE__{}

  schema "locations" do
    field :name, :string
    field :description, :string
    field :area, :string
    field :color, :string, default: "#4ae08a"
    field :private, :boolean, default: false
    field :status, :string
    field :status_updated_at, :utc_datetime

    belongs_to :story, Story
    belongs_to :zone, Zone
    belongs_to :guild, TannhauserGate.Guilds.Guild

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :description, :area, :color, :private, :zone_id, :guild_id])
    |> validate_required([:name, :area, :color])
    |> validate_length(:name, max: 120)
    |> validate_format(:area, @points_format,
      message:
        dgettext_noop("errors", "must be a list of at least 3 x,y points separated by spaces")
    )
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/,
      message: dgettext_noop("errors", "must be a hex color like #4ae08a")
    )
    |> foreign_key_constraint(:story_id)
    |> foreign_key_constraint(:zone_id)
    |> foreign_key_constraint(:guild_id)
    |> unique_constraint([:story_id, :name])
  end

  @doc "Changeset for the room status set by the masters."
  def status_changeset(location, status) do
    location
    |> change(status: status, status_updated_at: DateTime.utc_now(:second))
    |> update_change(:status, &(&1 && String.trim(&1)))
    |> validate_length(:status, max: 500)
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
