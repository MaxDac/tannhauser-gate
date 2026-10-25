defmodule TannhauserGate.Boards.Board do
  @moduledoc """
  An in-game notice board, hung in a room (location) or in a whole zone (shown
  in every room of the zone). It may be restricted to a guild (guilds
  module): only its active members' players and the masters see it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "boards" do
    field :name, :string
    field :description, :string

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :location, TannhauserGate.Stories.Location
    belongs_to :zone, TannhauserGate.Zones.Zone
    belongs_to :guild, TannhauserGate.Guilds.Guild

    has_many :notices, TannhauserGate.Boards.Notice

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset; the ids are checked against the story by `TannhauserGate.Boards`."
  def changeset(board, attrs) do
    board
    |> cast(attrs, [:name, :description, :location_id, :zone_id, :guild_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_place()
    |> check_constraint(:location_id, name: :boards_place_check, message: "pick a room or a zone")
  end

  defp validate_place(changeset) do
    case {get_field(changeset, :location_id), get_field(changeset, :zone_id)} do
      {nil, nil} -> add_error(changeset, :location_id, "pick a room or a zone")
      {_, nil} -> changeset
      {nil, _} -> changeset
      _ -> add_error(changeset, :zone_id, "pick either a room or a zone, not both")
    end
  end
end
