defmodule TannhauserGate.CalendarTest do
  use ExUnit.Case, async: true

  alias TannhauserGate.Calendar, as: GameCalendar
  alias TannhauserGate.Calendar.Config

  doctest TannhauserGate.Calendar

  @epoch ~U[2026-01-01 00:00:00Z]

  defp config(attrs \\ %{}) do
    struct(
      %Config{
        epoch_real: @epoch,
        epoch_year: 2121,
        epoch_month: 1,
        epoch_day: 1,
        epoch_hour: 0,
        epoch_minute: 0,
        ratio: 1,
        month_names: ~w(Ashfall Coldwire Thawrain),
        days_per_month: [3, 2, 4],
        seasons: ["Winter", "", "Spring"],
        weekday_names: ~w(Mon Tue Wed),
        year_suffix: "AE"
      },
      attrs
    )
  end

  defp at(seconds), do: DateTime.add(@epoch, seconds, :second)

  test "the epoch maps to the epoch game date" do
    assert %{
             year: 2121,
             month: 1,
             month_name: "Ashfall",
             day: 1,
             hour: 0,
             minute: 0,
             season: "Winter",
             era: "AE"
           } = GameCalendar.to_game(config(), @epoch)
  end

  test "days, months and years roll over with custom month lengths" do
    day = 86_400
    assert %{month: 1, day: 3} = GameCalendar.to_game(config(), at(2 * day))

    assert %{month: 2, day: 1, month_name: "Coldwire", season: nil} =
             GameCalendar.to_game(config(), at(3 * day))

    assert %{month: 3, day: 1, season: "Spring"} = GameCalendar.to_game(config(), at(5 * day))
    assert %{month: 3, day: 4} = GameCalendar.to_game(config(), at(8 * day))
    # 9 days a year
    assert %{year: 2122, month: 1, day: 1} = GameCalendar.to_game(config(), at(9 * day))

    assert %{year: 2120, month: 3, day: 4, hour: 23, minute: 59} =
             GameCalendar.to_game(config(), at(-60))
  end

  test "the ratio speeds the clock up" do
    assert %{hour: 0, minute: 1} = GameCalendar.to_game(config(), at(60))
    assert %{hour: 0, minute: 4} = GameCalendar.to_game(config(ratio: 4), at(60))
    assert %{day: 2, hour: 0} = GameCalendar.to_game(config(ratio: 24), at(3600))
    assert %{minute: 0} = GameCalendar.to_game(config(ratio: 4), at(14))
    assert %{minute: 1} = GameCalendar.to_game(config(ratio: 4), at(15))
  end

  test "weekdays cycle every day" do
    days = for n <- 0..5, do: GameCalendar.to_game(config(), at(n * 86_400)).weekday_name
    assert Enum.chunk_every(days, 3) |> Enum.uniq() |> length() == 1
    assert Enum.uniq(days) |> length() == 3
    assert GameCalendar.to_game(config(weekday_names: []), @epoch).weekday_name == nil
  end

  test "game time is monotonic and round-trips through absolute minutes" do
    cfg = config(ratio: 7)

    Enum.reduce(1..300, {GameCalendar.minutes_at(cfg, @epoch), @epoch}, fn n, {previous, real} ->
      real = DateTime.add(real, n * 997, :second)
      minutes = GameCalendar.minutes_at(cfg, real)
      assert minutes >= previous
      date = GameCalendar.from_minutes(minutes, cfg)
      assert GameCalendar.to_minutes(cfg, date) == minutes
      assert date.day in 1..Enum.at(cfg.days_per_month, date.month - 1)
      assert date.hour in 0..23 and date.minute in 0..59
      {minutes, real}
    end)
  end

  test "anchor/2 makes the given date current" do
    now = ~U[2030-05-05 12:00:00Z]
    game = %{year: 3000, month: 2, day: 2, hour: 22, minute: 15}
    cfg = struct(config(), GameCalendar.anchor(game, now))

    assert %{year: 3000, month: 2, day: 2, hour: 22, minute: 15} = GameCalendar.to_game(cfg, now)
    assert %{hour: 22, minute: 16} = GameCalendar.to_game(cfg, DateTime.add(now, 60))
  end

  test "format/2" do
    date = GameCalendar.to_game(config(), at(3 * 86_400 + 9 * 3600 + 5 * 60))
    assert GameCalendar.format(date) == "Mon, 1 Coldwire 2121 AE · 09:05"
    assert GameCalendar.format(date, :date) == "1 Coldwire 2121 AE"
    assert GameCalendar.format(date, :time) == "09:05"

    plain = GameCalendar.to_game(config(year_suffix: nil, weekday_names: []), @epoch)
    assert GameCalendar.format(plain) == "1 Ashfall 2121 · 00:00"
  end

  describe "config changeset" do
    test "parses the months text" do
      changeset =
        Config.changeset(%Config{}, %{
          "ratio" => "2",
          "months_text" => "Rain | 10 | Wet\nDust\n\nAsh | 5",
          "weekdays_text" => "One, Two",
          "epoch_year" => "2121",
          "epoch_month" => "2",
          "epoch_day" => "30",
          "epoch_hour" => "0",
          "epoch_minute" => "0"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :month_names) == ~w(Rain Dust Ash)
      assert Ecto.Changeset.get_field(changeset, :days_per_month) == [10, 30, 5]
      assert Ecto.Changeset.get_field(changeset, :seasons) == ["Wet", "", ""]
      assert Ecto.Changeset.get_field(changeset, :weekday_names) == ~w(One Two)
    end

    test "rejects bad lines, out-of-range days and ratios" do
      base = %{
        "ratio" => "1",
        "months_text" => "A | 10",
        "epoch_year" => "1",
        "epoch_month" => "1",
        "epoch_day" => "1",
        "epoch_hour" => "0",
        "epoch_minute" => "0"
      }

      refute Config.changeset(%Config{}, %{base | "months_text" => "A | x"}).valid?
      refute Config.changeset(%Config{}, %{base | "months_text" => ""}).valid?
      refute Config.changeset(%Config{}, %{base | "epoch_day" => "11"}).valid?
      refute Config.changeset(%Config{}, %{base | "epoch_month" => "2"}).valid?
      refute Config.changeset(%Config{}, %{base | "ratio" => "0"}).valid?
      refute Config.changeset(%Config{}, %{base | "epoch_hour" => "24"}).valid?
    end

    test "months_text/1 round-trips" do
      cfg = config()

      assert Config.months_text(cfg) ==
               "Ashfall | 3 | Winter\nColdwire | 2\nThawrain | 4 | Spring"
    end
  end
end
