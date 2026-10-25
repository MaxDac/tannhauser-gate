defmodule TannhauserGate.Weather.ZoneWeather do
  @moduledoc """
  The current weather of a zone (weather module): condition, icon, optional
  temperature and description. `set_by` is `"master"` (set by hand, by
  `user`) or `"generated"` (rolled from the weather table). The roller leaves
  the zone alone until `expires_at` (set time + the GDR weather interval).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Weather.Condition

  @sources ~w(master generated)

  schema "zone_weathers" do
    field :condition, :string
    field :icon, :string, default: "hero-cloud"
    field :temperature, :integer
    field :description, :string
    field :set_by, :string, default: "master"
    field :set_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :zone, TannhauserGate.Zones.Zone
    belongs_to :user, TannhauserGate.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the fields a master sets; the rest is set by `TannhauserGate.Weather`."
  def changeset(weather, attrs) do
    weather
    |> cast(attrs, [:condition, :icon, :temperature, :description])
    |> update_change(:condition, &String.trim/1)
    |> validate_required([:condition, :icon])
    |> validate_length(:condition, max: 60)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:icon, Condition.icon_names())
    |> validate_number(:temperature, greater_than_or_equal_to: -100, less_than_or_equal_to: 100)
    |> validate_inclusion(:set_by, @sources)
  end
end
