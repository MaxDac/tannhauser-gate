defmodule TannhauserGate.Zones.Zone do
  @moduledoc """
  A zone groups locations of a GDR and carries a value for each of the
  GDR's zone properties (`values`, property slug => integer).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.{Location, Story}
  alias TannhauserGate.Zones.Event

  schema "zones" do
    field :name, :string
    field :description, :string
    field :values, :map, default: %{}

    belongs_to :story, Story
    has_many :locations, Location
    has_many :events, Event

    timestamps(type: :utc_datetime)
  end

  @doc """
  `slugs` are the property slugs of the GDR: values for other keys are
  dropped, values must be integers between -1000 and 1000.
  """
  def changeset(zone, attrs, slugs) do
    zone
    |> cast(attrs, [:name, :description, :values])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 5_000)
    |> normalize_values(slugs)
    |> unique_constraint([:story_id, :name],
      error_key: :name,
      name: :zones_story_id_name_index,
      message: "is already used by another zone"
    )
  end

  defp normalize_values(changeset, slugs) do
    case fetch_change(changeset, :values) do
      {:ok, values} when is_map(values) ->
        values |> parse_values(slugs) |> put_values(changeset)

      _ ->
        changeset
    end
  end

  defp parse_values(values, slugs) do
    for {slug, raw} <- values, to_string(slug) in slugs, into: %{} do
      {to_string(slug), parse(raw)}
    end
  end

  defp put_values(parsed, changeset) do
    if Enum.all?(parsed, fn {_, v} -> is_integer(v) and v in -1_000..1_000 end),
      do: put_change(changeset, :values, parsed),
      else: add_error(changeset, :values, "must be whole numbers between -1000 and 1000")
  end

  defp parse(value) when is_integer(value), do: value

  defp parse(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp parse(_), do: :error
end
