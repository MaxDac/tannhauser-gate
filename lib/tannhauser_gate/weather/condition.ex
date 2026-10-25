defmodule TannhauserGate.Weather.Condition do
  @moduledoc """
  A row of the GDR weather table (weather module): a condition with its icon,
  its weight per season (`weights`, season name => weight) and optional
  temperature range per season (`temp_min`/`temp_max`, season name => °C).
  Without calendar seasons the season is `"default"`, which is also the
  fallback for seasons missing from the maps.
  """
  use Ecto.Schema
  import Ecto.Changeset

  # Literal class names so Tailwind generates them.
  @icons [
    {"Clear (sun)", "hero-sun"},
    {"Clear night (moon)", "hero-moon"},
    {"Clouds", "hero-cloud"},
    {"Rain", "hero-cloud-arrow-down"},
    {"Storm", "hero-bolt"},
    {"Fog / smog", "hero-eye-slash"},
    {"Acid", "hero-beaker"},
    {"Heat / fire", "hero-fire"},
    {"Neon / glow", "hero-sparkles"},
    {"Wind / dust", "hero-globe-alt"},
    {"Interference", "hero-signal-slash"},
    {"Hazard", "hero-exclamation-triangle"}
  ]

  @icon_names Enum.map(@icons, &elem(&1, 1))

  @doc "The selectable icons, as `{label, icon}` options."
  def icons, do: @icons

  def icon_names, do: @icon_names

  schema "weather_conditions" do
    field :name, :string
    field :icon, :string, default: "hero-cloud"
    field :description, :string
    field :weights, :map, default: %{}
    field :temp_min, :map, default: %{}
    field :temp_max, :map, default: %{}

    belongs_to :story, TannhauserGate.Stories.Story

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [:name, :icon, :description, :weights, :temp_min, :temp_max])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :icon])
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:icon, @icon_names)
    |> normalize(:weights, 0..1000, "weights must be whole numbers between 0 and 1000")
    |> normalize(:temp_min, -100..100, "temperatures must be between -100 and 100")
    |> normalize(:temp_max, -100..100, "temperatures must be between -100 and 100")
    |> unique_constraint([:story_id, :name],
      error_key: :name,
      name: :weather_conditions_story_id_name_index,
      message: "is already in the table"
    )
  end

  # Blank values are dropped, the others must be integers in `range`.
  defp normalize(changeset, field, range, message) do
    case fetch_change(changeset, field) do
      {:ok, map} when is_map(map) ->
        parsed =
          for {season, raw} <- map,
              raw not in [nil, ""],
              season = season |> to_string() |> String.trim(),
              season != "" and String.length(season) <= 40,
              into: %{},
              do: {season, parse(raw)}

        if Enum.all?(parsed, fn {_, v} -> is_integer(v) and v in range end),
          do: put_change(changeset, field, parsed),
          else: add_error(changeset, field, message)

      _ ->
        changeset
    end
  end

  defp parse(value) when is_integer(value), do: value

  defp parse(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> :error
    end
  end

  defp parse(_), do: :error

  @doc "The weight of the condition in `season` (falling back to `\"default\"`)."
  def weight(%__MODULE__{weights: weights}, season),
    do: Map.get(weights, season) || Map.get(weights, "default") || 0

  @doc "The `{min, max}` temperature range in `season`, or nil."
  def temperature_range(%__MODULE__{temp_min: mins, temp_max: maxs}, season) do
    min = Map.get(mins, season) || Map.get(mins, "default")
    max = Map.get(maxs, season) || Map.get(maxs, "default")

    if is_integer(min) and is_integer(max), do: {min(min, max), max(min, max)}
  end
end
