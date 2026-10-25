defmodule TannhauserGate.Calendar do
  @moduledoc """
  The pure math of the game calendar (calendar module): converts real
  instants to game dates for a `TannhauserGate.Calendar.Config` and formats
  them. No database access here; see `TannhauserGate.Calendars` for that.

  Game dates are counted in "absolute minutes": the minutes elapsed since
  year 0, month 1, day 1, 00:00 of the custom calendar. A real instant maps
  to `epoch minutes + floor(elapsed real seconds × ratio / 60)`. Weekdays
  cycle from absolute day 0. The same math runs in the browser to advance
  the displayed clock (see `TannhauserGateWeb.CalendarComponents`).

  Not to be confused with Elixir's `Calendar`: alias it as `GameCalendar`.
  """

  @minutes_per_day 1440

  @typedoc "A game date."
  @type game_date :: %{
          year: integer(),
          month: pos_integer(),
          month_name: String.t(),
          day: pos_integer(),
          weekday_name: String.t() | nil,
          hour: non_neg_integer(),
          minute: non_neg_integer(),
          season: String.t() | nil,
          era: String.t() | nil
        }

  @doc "The game date at the real instant `real` (now by default)."
  def to_game(config, real \\ DateTime.utc_now()) do
    config |> minutes_at(real) |> from_minutes(config)
  end

  @doc "The absolute game minute at the real instant `real`."
  def minutes_at(config, %DateTime{} = real) do
    elapsed = DateTime.diff(real, config.epoch_real, :second)
    epoch_minutes(config) + Integer.floor_div(elapsed * config.ratio, 60)
  end

  @doc "The absolute minute of the calendar's epoch game date."
  def epoch_minutes(config) do
    to_minutes(config, %{
      year: config.epoch_year,
      month: config.epoch_month,
      day: config.epoch_day,
      hour: config.epoch_hour,
      minute: config.epoch_minute
    })
  end

  @doc "The absolute minute of a game date (a map with year, month, day, hour and minute)."
  def to_minutes(config, %{year: year, month: month, day: day, hour: hour, minute: minute}) do
    days =
      year * days_per_year(config) + Enum.sum(Enum.take(config.days_per_month, month - 1)) +
        (day - 1)

    days * @minutes_per_day + hour * 60 + minute
  end

  @doc "The game date of an absolute minute."
  def from_minutes(minutes, config) do
    abs_day = Integer.floor_div(minutes, @minutes_per_day)
    minute_of_day = Integer.mod(minutes, @minutes_per_day)
    year = Integer.floor_div(abs_day, days_per_year(config))

    {month, day} =
      month_and_day(config.days_per_month, Integer.mod(abs_day, days_per_year(config)), 1)

    %{
      year: year,
      month: month,
      month_name: Enum.at(config.month_names, month - 1),
      day: day,
      weekday_name: weekday(config.weekday_names, abs_day),
      hour: div(minute_of_day, 60),
      minute: rem(minute_of_day, 60),
      season: blank_to_nil(Enum.at(config.seasons || [], month - 1)),
      era: blank_to_nil(config.year_suffix)
    }
  end

  defp month_and_day([days | rest], day_of_year, month) do
    if day_of_year < days or rest == [],
      do: {month, day_of_year + 1},
      else: month_and_day(rest, day_of_year - days, month + 1)
  end

  defp weekday([], _abs_day), do: nil
  defp weekday(names, abs_day), do: Enum.at(names, Integer.mod(abs_day, length(names)))

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  @doc "The days in a game year."
  def days_per_year(config), do: max(Enum.sum(config.days_per_month), 1)

  @doc """
  Re-anchors the calendar so that the real instant `real` is the game date
  `game` (a map with year, month, day, hour and minute): the changes to apply.
  """
  def anchor(%{year: year, month: month, day: day, hour: hour, minute: minute}, real) do
    %{
      epoch_real: DateTime.truncate(real, :second),
      epoch_year: year,
      epoch_month: month,
      epoch_day: day,
      epoch_hour: hour,
      epoch_minute: minute
    }
  end

  @doc """
  Formats a game date. Styles: `:full` (weekday, date and time, the
  default), `:date` (date only) and `:time` (hours and minutes).

      iex> TannhauserGate.Calendar.format(%{year: 2121, month: 3, month_name: "March",
      ...>   day: 4, weekday_name: "Tuesday", hour: 9, minute: 5, season: nil, era: "AE"})
      "Tuesday, 4 March 2121 AE · 09:05"
  """
  def format(date, style \\ :full)

  def format(date, :time), do: "#{pad(date.hour)}:#{pad(date.minute)}"

  def format(date, :date) do
    era = if date.era, do: " #{date.era}", else: ""
    "#{date.day} #{date.month_name} #{date.year}#{era}"
  end

  def format(date, :full) do
    weekday = if date.weekday_name, do: "#{date.weekday_name}, ", else: ""
    "#{weekday}#{format(date, :date)} · #{format(date, :time)}"
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
