defmodule TannhauserGate.Calendar.Config do
  @moduledoc """
  The game calendar of a GDR (calendar module), 1:1 with the story.

  The game clock is anchored at `epoch_real` (a real UTC instant) which
  corresponds to the game date `epoch_year`-`epoch_month`-`epoch_day`
  `epoch_hour`:`epoch_minute`; from there game time runs `ratio` times faster
  than real time. The year has one month per `month_names` entry, each
  lasting the matching `days_per_month` days and optionally belonging to the
  matching `seasons` entry (used by the weather module). Weeks cycle through
  `weekday_names`, when given. See `TannhauserGate.Calendar` for the math.

  The months are edited as text (`months_text`): one month per line,
  `Name | days | season` (days default to 30, the season is optional).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_months 24
  @default_days 30

  schema "calendars" do
    field :epoch_real, :utc_datetime
    field :epoch_year, :integer, default: 1
    field :epoch_month, :integer, default: 1
    field :epoch_day, :integer, default: 1
    field :epoch_hour, :integer, default: 0
    field :epoch_minute, :integer, default: 0
    field :ratio, :integer, default: 1
    field :month_names, {:array, :string}, default: []
    field :days_per_month, {:array, :integer}, default: []
    field :seasons, {:array, :string}, default: []
    field :weekday_names, {:array, :string}, default: []
    field :year_suffix, :string

    field :months_text, :string, virtual: true
    field :weekdays_text, :string, virtual: true

    belongs_to :story, TannhauserGate.Stories.Story

    timestamps(type: :utc_datetime)
  end

  @doc """
  GM changeset: the structure (months, weekdays, era, ratio) and the game date
  the clock is re-anchored to. `epoch_real` is set by `TannhauserGate.Calendars`.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:ratio, :year_suffix, :months_text, :weekdays_text])
    |> validate_required([:ratio])
    |> validate_number(:ratio, greater_than_or_equal_to: 1, less_than_or_equal_to: 1000)
    |> validate_length(:year_suffix, max: 20)
    |> parse_months()
    |> parse_weekdays()
    |> date_changeset(attrs)
  end

  @doc "Changeset for the game date only (master override)."
  def date_changeset(config, attrs) do
    config
    |> cast(attrs, [:epoch_year, :epoch_month, :epoch_day, :epoch_hour, :epoch_minute])
    |> validate_required([:epoch_year, :epoch_month, :epoch_day, :epoch_hour, :epoch_minute])
    |> validate_number(:epoch_year, greater_than_or_equal_to: -100_000, less_than: 100_000)
    |> validate_number(:epoch_hour, greater_than_or_equal_to: 0, less_than: 24)
    |> validate_number(:epoch_minute, greater_than_or_equal_to: 0, less_than: 60)
    |> validate_day()
  end

  defp validate_day(changeset) do
    months = get_field(changeset, :days_per_month) || []
    month = get_field(changeset, :epoch_month)
    day = get_field(changeset, :epoch_day)

    cond do
      not is_integer(month) or not is_integer(day) ->
        changeset

      month < 1 or month > length(months) ->
        add_error(changeset, :epoch_month, "must be between 1 and #{max(length(months), 1)}")

      day < 1 or day > Enum.at(months, month - 1) ->
        add_error(changeset, :epoch_day, "must be between 1 and #{Enum.at(months, month - 1)}")

      true ->
        changeset
    end
  end

  defp parse_months(changeset) do
    case get_change(changeset, :months_text) do
      nil ->
        if get_field(changeset, :month_names) == [],
          do: add_error(changeset, :months_text, "can't be blank"),
          else: changeset

      text ->
        text |> lines() |> Enum.map(&parse_month/1) |> put_months(changeset)
    end
  end

  defp put_months([], changeset), do: add_error(changeset, :months_text, "can't be blank")

  defp put_months(months, changeset) do
    cond do
      length(months) > @max_months ->
        add_error(changeset, :months_text, "can have at most #{@max_months} months")

      Enum.any?(months, &(&1 == :error)) ->
        add_error(
          changeset,
          :months_text,
          "each line must be \"Name | days (1-100) | season\" (names up to 30 characters)"
        )

      true ->
        changeset
        |> put_change(:month_names, Enum.map(months, &elem(&1, 0)))
        |> put_change(:days_per_month, Enum.map(months, &elem(&1, 1)))
        |> put_change(:seasons, Enum.map(months, &elem(&1, 2)))
    end
  end

  defp parse_month(line) do
    case line |> String.split("|") |> Enum.map(&String.trim/1) do
      [name] -> month(name, "", "")
      [name, days] -> month(name, days, "")
      [name, days, season] -> month(name, days, season)
      _ -> :error
    end
  end

  defp month(name, days, season) do
    with true <- name != "" and String.length(name) <= 30 and String.length(season) <= 30,
         {:ok, days} <- parse_days(days) do
      {name, days, season}
    else
      _ -> :error
    end
  end

  defp parse_days(""), do: {:ok, @default_days}

  defp parse_days(days) do
    case Integer.parse(days) do
      {n, ""} when n in 1..100 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_weekdays(changeset) do
    case get_change(changeset, :weekdays_text) do
      nil ->
        changeset

      text ->
        names =
          text
          |> String.split([",", "\n"])
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        if length(names) > 14 or Enum.any?(names, &(String.length(&1) > 30)),
          do: add_error(changeset, :weekdays_text, "at most 14 names of up to 30 characters"),
          else: put_change(changeset, :weekday_names, names)
    end
  end

  defp lines(text) do
    text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @doc "The months of the config as editable text (see the moduledoc)."
  def months_text(%__MODULE__{} = config) do
    [config.month_names, config.days_per_month, pad(config.seasons, length(config.month_names))]
    |> Enum.zip()
    |> Enum.map_join("\n", fn
      {name, days, ""} -> "#{name} | #{days}"
      {name, days, season} -> "#{name} | #{days} | #{season}"
    end)
  end

  @doc "The weekday names as editable text."
  def weekdays_text(%__MODULE__{weekday_names: names}), do: Enum.join(names, ", ")

  defp pad(list, n), do: Enum.take(list ++ List.duplicate("", n), n)
end
