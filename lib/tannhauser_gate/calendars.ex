defmodule TannhauserGate.Calendars do
  @moduledoc """
  The game calendar of a GDR (calendar module): its configuration
  (`TannhauserGate.Calendar.Config`, set by the GDR admin), the master
  override of the current game date and the current game date itself. The
  math lives in the pure `TannhauserGate.Calendar`.

  Every change is broadcast on `"calendar:story:<id>"` as
  `{:calendar_changed, config}` so the displayed clocks re-anchor.
  """

  alias TannhauserGate.Calendar, as: GameCalendar
  alias TannhauserGate.Calendar.Config
  alias TannhauserGate.{Repo, Stories}
  alias TannhauserGate.Stories.Story

  @default_months [
    {"January", 31, "Winter"},
    {"February", 28, "Winter"},
    {"March", 31, "Spring"},
    {"April", 30, "Spring"},
    {"May", 31, "Spring"},
    {"June", 30, "Summer"},
    {"July", 31, "Summer"},
    {"August", 31, "Summer"},
    {"September", 30, "Autumn"},
    {"October", 31, "Autumn"},
    {"November", 30, "Autumn"},
    {"December", 31, "Winter"}
  ]

  @default_weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  @doc "Whether the calendar module is on for the story."
  def enabled?(story), do: Stories.module_enabled?(story, :calendar)

  @doc "The PubSub topic of the story's calendar changes."
  def topic(story_id), do: "calendar:story:#{story_id}"

  def subscribe(story_id), do: Phoenix.PubSub.subscribe(TannhauserGate.PubSub, topic(story_id))

  @doc "The saved calendar of the story, or nil."
  def get_calendar(%Story{id: story_id}), do: Repo.get_by(Config, story_id: story_id)

  @doc """
  The story with its `calendar` preloaded when the module is on (nil
  otherwise), for the layout clock.
  """
  def preload(%Story{} = story) do
    if enabled?(story),
      do: Repo.preload(story, :calendar, force: true),
      else: %{story | calendar: nil}
  end

  @doc "A real-world-like calendar starting now, used until the GDR admin saves one."
  def default_config(%Story{id: story_id}, now \\ DateTime.utc_now()) do
    %Config{
      story_id: story_id,
      epoch_real: DateTime.truncate(now, :second),
      epoch_year: now.year,
      epoch_month: now.month,
      epoch_day: now.day,
      epoch_hour: now.hour,
      epoch_minute: now.minute,
      month_names: Enum.map(@default_months, &elem(&1, 0)),
      days_per_month: Enum.map(@default_months, &elem(&1, 1)),
      seasons: Enum.map(@default_months, &elem(&1, 2)),
      weekday_names: @default_weekdays
    }
  end

  @doc "The saved calendar of the story, or the default one."
  def get_or_default(story), do: get_calendar(story) || default_config(story)

  @doc """
  The config ready for the GM form: the virtual text fields filled and the
  epoch fields set to the current game date (saving re-anchors there).
  """
  def form_config(%Config{} = config, now \\ DateTime.utc_now()) do
    game = GameCalendar.to_game(config, now)

    %{
      config
      | months_text: Config.months_text(config),
        weekdays_text: Config.weekdays_text(config),
        epoch_year: game.year,
        epoch_month: game.month,
        epoch_day: game.day,
        epoch_hour: game.hour,
        epoch_minute: game.minute
    }
  end

  def change_calendar(%Config{} = config, attrs \\ %{}), do: Config.changeset(config, attrs)

  def change_date(%Config{} = config, attrs \\ %{}), do: Config.date_changeset(config, attrs)

  @doc """
  GDR admin: saves the calendar structure and re-anchors it so `now` is the
  given game date.
  """
  def save_calendar(%Story{} = story, attrs, now \\ DateTime.utc_now()) do
    story
    |> get_or_default()
    |> Config.changeset(attrs)
    |> Ecto.Changeset.put_change(:epoch_real, DateTime.truncate(now, :second))
    |> Repo.insert_or_update()
    |> broadcast()
  end

  @doc """
  Master override: the current game date becomes the given one (re-anchors
  `epoch_real` to `now`). Ratio and months are unchanged.
  """
  def set_now(%Story{} = story, attrs, now \\ DateTime.utc_now()) do
    story
    |> get_or_default()
    |> Config.date_changeset(attrs)
    |> Ecto.Changeset.put_change(:epoch_real, DateTime.truncate(now, :second))
    |> Repo.insert_or_update()
    |> broadcast()
  end

  defp broadcast({:ok, config} = result) do
    Phoenix.PubSub.broadcast(
      TannhauserGate.PubSub,
      topic(config.story_id),
      {:calendar_changed, config}
    )

    result
  end

  defp broadcast(error), do: error

  @doc "The current game date of the story, or nil when the module is off or unset."
  def now(%Story{} = story, real \\ DateTime.utc_now()) do
    with true <- enabled?(story),
         %Config{} = config <- loaded_or_fetch(story) do
      GameCalendar.to_game(config, real)
    else
      _ -> nil
    end
  end

  @doc "The current game date formatted (`:full`), or nil (module off or unset)."
  def current_label(%Story{} = story, real \\ DateTime.utc_now()) do
    case now(story, real) do
      nil -> nil
      date -> GameCalendar.format(date)
    end
  end

  @doc ~s(The current season name of the story, "default" without calendar or season.)
  def current_season(%Story{} = story, real \\ DateTime.utc_now()) do
    case now(story, real) do
      %{season: season} when is_binary(season) -> season
      _ -> "default"
    end
  end

  @doc "The distinct season names of the story's calendar (empty without one)."
  def seasons(%Story{} = story) do
    with true <- enabled?(story),
         %Config{seasons: seasons} <- loaded_or_fetch(story) do
      seasons |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()
    else
      _ -> []
    end
  end

  defp loaded_or_fetch(%Story{calendar: %Config{} = config}), do: config
  defp loaded_or_fetch(story), do: get_calendar(story)
end
