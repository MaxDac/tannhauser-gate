defmodule TannhauserGate.Weather.Condition do
  use Gettext, backend: TannhauserGateWeb.Gettext

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
    {dgettext_noop("domain", "Clear (sun)"), "hero-sun"},
    {dgettext_noop("domain", "Clear night (moon)"), "hero-moon"},
    {dgettext_noop("domain", "Clouds"), "hero-cloud"},
    {dgettext_noop("domain", "Rain"), "hero-cloud-arrow-down"},
    {dgettext_noop("domain", "Storm"), "hero-bolt"},
    {dgettext_noop("domain", "Fog / smog"), "hero-eye-slash"},
    {dgettext_noop("domain", "Acid"), "hero-beaker"},
    {dgettext_noop("domain", "Heat / fire"), "hero-fire"},
    {dgettext_noop("domain", "Neon / glow"), "hero-sparkles"},
    {dgettext_noop("domain", "Wind / dust"), "hero-globe-alt"},
    {dgettext_noop("domain", "Interference"), "hero-signal-slash"},
    {dgettext_noop("domain", "Hazard"), "hero-exclamation-triangle"}
  ]

  @icon_names Enum.map(@icons, &elem(&1, 1))

  @doc "The selectable icons, as `{label, icon}` options."
  def icons do
    for {label, icon} <- @icons,
        do: {Gettext.dgettext(TannhauserGateWeb.Gettext, "domain", label), icon}
  end

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
    |> normalize(
      :weights,
      0..1000,
      dgettext_noop("errors", "weights must be whole numbers between 0 and 1000")
    )
    |> normalize(
      :temp_min,
      -100..100,
      dgettext_noop("errors", "temperatures must be between -100 and 100")
    )
    |> normalize(
      :temp_max,
      -100..100,
      dgettext_noop("errors", "temperatures must be between -100 and 100")
    )
    |> unique_constraint([:story_id, :name],
      error_key: :name,
      name: :weather_conditions_story_id_name_index,
      message: dgettext_noop("errors", "is already in the table")
    )
  end

  # Blank values are dropped, the others must be integers in `range`.
  defp normalize(changeset, field, range, message) do
    case fetch_change(changeset, field) do
      {:ok, map} when is_map(map) ->
        parsed = parse_seasons(map)

        if all_in_range?(parsed, range),
          do: put_change(changeset, field, parsed),
          else: add_error(changeset, field, message)

      _ ->
        changeset
    end
  end

  defp all_in_range?(parsed, range),
    do: Enum.all?(parsed, fn {_, v} -> is_integer(v) and v in range end)

  defp parse_seasons(map) do
    for {season, raw} <- map,
        raw not in [nil, ""],
        season = season |> to_string() |> String.trim(),
        season != "" and String.length(season) <= 40,
        into: %{},
        do: {season, parse(raw)}
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
