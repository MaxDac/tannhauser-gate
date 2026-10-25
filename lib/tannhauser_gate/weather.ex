defmodule TannhauserGate.Weather do
  @moduledoc """
  Weather per zone (weather module).

  The GDR admin keeps a weather table (`TannhauserGate.Weather.Condition`):
  conditions weighted per season (the calendar seasons when the calendar
  module is on, otherwise a single `"default"` season). Every zone has a
  current weather (`TannhauserGate.Weather.ZoneWeather`), either set by a
  master or rolled from the table by `TannhauserGate.Weather.Roller` every
  `weather_interval_hours` of the GDR (`roll_due/2`). A weather set by a
  master is kept for one interval before the roller replaces it.

  Changes are broadcast on `"weather:story:<id>"` as `{:weather_changed, story_id}`.
  """

  import Ecto.Query

  alias TannhauserGate.{Calendars, Repo, Stories}
  alias TannhauserGate.Stories.Story
  alias TannhauserGate.Weather.{Condition, ZoneWeather}
  alias TannhauserGate.Zones.Zone

  @doc "Whether the weather module is on for the story."
  def enabled?(story), do: Stories.module_enabled?(story, :weather)

  def topic(story_id), do: "weather:story:#{story_id}"

  def subscribe(story_id), do: Phoenix.PubSub.subscribe(TannhauserGate.PubSub, topic(story_id))

  defp broadcast(story_id),
    do:
      Phoenix.PubSub.broadcast(
        TannhauserGate.PubSub,
        topic(story_id),
        {:weather_changed, story_id}
      )

  @doc """
  The seasons the weather table is weighted on: the calendar seasons when the
  calendar module is on and defines some, otherwise `["default"]`.
  """
  def seasons(%Story{} = story) do
    case Calendars.seasons(story) do
      [] -> ["default"]
      seasons -> seasons
    end
  end

  ## Weather table

  def list_conditions(%Story{id: story_id}) do
    Repo.all(from c in Condition, where: c.story_id == ^story_id, order_by: [asc: c.name])
  end

  def get_condition(%Story{id: story_id}, id) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> Repo.get_by(Condition, id: id, story_id: story_id)
      _ -> nil
    end
  end

  def create_condition(%Story{id: story_id}, attrs),
    do: %Condition{story_id: story_id} |> Condition.changeset(attrs) |> Repo.insert()

  def update_condition(%Story{id: story_id}, %Condition{story_id: story_id} = condition, attrs),
    do: condition |> Condition.changeset(attrs) |> Repo.update()

  def delete_condition(%Story{id: story_id}, %Condition{story_id: story_id} = condition),
    do: Repo.delete(condition)

  def change_condition(%Condition{} = condition, attrs \\ %{}),
    do: Condition.changeset(condition, attrs)

  @doc """
  Picks a condition of `conditions` weighted by `season`; nil when every
  weight is zero. `rand` gets the total weight `n` and returns an integer in
  `1..n` (`:rand.uniform/1` by default, inject one for deterministic tests).
  """
  def pick(conditions, season, rand \\ &:rand.uniform/1) do
    weighted =
      for condition <- conditions,
          weight = Condition.weight(condition, season),
          weight > 0,
          do: {condition, weight}

    case Enum.sum_by(weighted, &elem(&1, 1)) do
      0 -> nil
      total -> walk(weighted, rand.(total))
    end
  end

  defp walk([{condition, weight} | rest], roll) do
    if roll <= weight or rest == [], do: condition, else: walk(rest, roll - weight)
  end

  ## Zone weather

  @doc "The current weather of every zone of the story, by zone id."
  def zone_weathers(%Story{id: story_id}) do
    Repo.all(from w in ZoneWeather, where: w.story_id == ^story_id)
    |> Map.new(&{&1.zone_id, &1})
  end

  @doc "The current weather of the zone, or nil."
  def zone_weather(%Zone{id: zone_id}), do: Repo.get_by(ZoneWeather, zone_id: zone_id)
  def zone_weather(nil), do: nil

  def change_zone_weather(%ZoneWeather{} = weather, attrs \\ %{}),
    do: ZoneWeather.changeset(weather, attrs)

  defp get_zone(%Story{id: story_id}, zone_id) do
    case Integer.parse(to_string(zone_id)) do
      {id, ""} -> Repo.get_by(Zone, id: id, story_id: story_id)
      _ -> nil
    end
  end

  @doc """
  A master sets the weather of a zone of the story by hand. The roller keeps
  it for one weather interval.
  """
  def set_zone_weather(%Story{} = story, zone_id, user, attrs, now \\ DateTime.utc_now()) do
    case get_zone(story, zone_id) do
      nil ->
        {:error, :zone_not_found}

      zone ->
        %ZoneWeather{set_by: "master", user_id: user && user.id}
        |> ZoneWeather.changeset(attrs)
        |> upsert(story, zone, now)
    end
  end

  @doc "Removes the weather of a zone of the story (the roller sets a new one)."
  def clear_zone_weather(%Story{} = story, zone_id) do
    case get_zone(story, zone_id) do
      nil ->
        {:error, :zone_not_found}

      zone ->
        Repo.delete_all(from w in ZoneWeather, where: w.zone_id == ^zone.id)
        broadcast(story.id)
        :ok
    end
  end

  @doc """
  Rolls the weather of a zone of the story from its table for the current
  season. Options: `:rand` (see `pick/3`), `:season`.
  """
  def roll_zone(%Story{} = story, zone_id, now \\ DateTime.utc_now(), opts \\ []) do
    with %Zone{} = zone <- get_zone(story, zone_id) || {:error, :zone_not_found},
         season = Keyword.get_lazy(opts, :season, fn -> Calendars.current_season(story, now) end),
         %Condition{} = condition <-
           pick(list_conditions(story), season, rand(opts)) || {:error, :empty_table} do
      roll_condition(story, zone, condition, season, now, opts)
    end
  end

  defp rand(opts), do: Keyword.get(opts, :rand, &:rand.uniform/1)

  defp roll_condition(story, zone, condition, season, now, opts) do
    temperature =
      case Condition.temperature_range(condition, season) do
        {min, max} -> min + rand(opts).(max - min + 1) - 1
        nil -> nil
      end

    %ZoneWeather{
      set_by: "generated",
      condition: condition.name,
      icon: condition.icon,
      temperature: temperature,
      description: condition.description
    }
    |> Ecto.Changeset.change()
    |> upsert(story, zone, now)
  end

  defp upsert(changeset, story, zone, now) do
    now = DateTime.truncate(now, :second)

    changeset
    |> Ecto.Changeset.change(
      story_id: story.id,
      zone_id: zone.id,
      set_at: now,
      expires_at: DateTime.add(now, story.weather_interval_hours * 3600, :second)
    )
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :condition,
           :icon,
           :temperature,
           :description,
           :set_by,
           :user_id,
           :set_at,
           :expires_at,
           :updated_at
         ]},
      conflict_target: :zone_id,
      returning: true
    )
    |> case do
      {:ok, weather} ->
        broadcast(story.id)
        {:ok, weather}

      error ->
        error
    end
  end

  ## Roller

  @doc """
  Rolls a new weather for every due zone of the stories with the weather
  module on: zones without weather or whose weather expired at `now` (a
  weather set by a master lasts one interval). Returns the number of zones
  rolled. Options: `:rand` (see `pick/3`).
  """
  def roll_due(now \\ DateTime.utc_now(), opts \\ []) do
    from(s in Story, where: fragment("coalesce((?->>'weather')::boolean, false)", s.modules))
    |> Repo.all()
    |> Enum.map(&roll_story_due(&1, now, opts))
    |> Enum.sum()
  end

  @doc "Rolls the due zones of one story (see `roll_due/2`)."
  def roll_story_due(%Story{} = story, now \\ DateTime.utc_now(), opts \\ []) do
    conditions = list_conditions(story)

    if enabled?(story) and conditions != [] do
      season = Calendars.current_season(story, now)

      story
      |> due_zones(now)
      |> Enum.count(fn zone ->
        case pick(conditions, season, rand(opts)) do
          nil -> false
          condition -> match?({:ok, _}, roll_condition(story, zone, condition, season, now, opts))
        end
      end)
    else
      0
    end
  end

  defp due_zones(%Story{id: story_id}, now) do
    now = DateTime.truncate(now, :second)

    Repo.all(
      from z in Zone,
        left_join: w in ZoneWeather,
        on: w.zone_id == z.id,
        where: z.story_id == ^story_id and (is_nil(w.id) or w.expires_at <= ^now),
        order_by: [asc: z.id]
    )
  end
end
