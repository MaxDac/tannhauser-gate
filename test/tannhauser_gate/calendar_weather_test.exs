defmodule TannhauserGate.CalendarWeatherTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Calendars, Esiti, Repo, Weather, Zones}
  alias TannhauserGate.Weather.{Condition, ZoneWeather}

  @months "Ashfall | 30 | Winter\nNeonbloom | 30 | Summer"

  defp calendar_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "months_text" => @months,
      "weekdays_text" => "Mon, Tue",
      "ratio" => "1",
      "year_suffix" => "AE",
      "epoch_year" => "2121",
      "epoch_month" => "1",
      "epoch_day" => "1",
      "epoch_hour" => "12",
      "epoch_minute" => "0"
    })
  end

  defp zone!(story, name) do
    {:ok, zone} = Zones.create_zone(story, %{name: name})
    zone
  end

  defp condition!(story, name, weights, attrs \\ %{}) do
    {:ok, condition} =
      Weather.create_condition(
        story,
        Enum.into(attrs, %{"name" => name, "icon" => "hero-cloud", "weights" => weights})
      )

    condition
  end

  describe "calendars" do
    test "now/2 is nil while the module is off or unset" do
      {story, _gm} = gdr_fixture()
      assert Calendars.now(story) == nil
      story = enable_modules(story, [:calendar])
      assert Calendars.now(story) == nil
      assert Calendars.current_season(story) == "default"
    end

    test "save_calendar/3 anchors the given date at now and the clock runs" do
      {story, _gm} = gdr_fixture()
      story = enable_modules(story, [:calendar])
      now = ~U[2026-10-25 10:00:00Z]

      assert {:ok, config} = Calendars.save_calendar(story, calendar_attrs(), now)
      assert config.month_names == ~w(Ashfall Neonbloom)

      assert %{year: 2121, month: 1, day: 1, hour: 12, season: "Winter"} =
               Calendars.now(story, now)

      assert Calendars.current_label(story, DateTime.add(now, 90, :minute)) =~
               "1 Ashfall 2121 AE · 13:30"

      assert Calendars.current_season(story, DateTime.add(now, 30, :day)) == "Summer"
      assert Calendars.seasons(story) == ~w(Winter Summer)

      assert {:error, changeset} =
               Calendars.save_calendar(story, calendar_attrs(%{"epoch_day" => "31"}), now)

      assert %{epoch_day: [_]} = errors_on(changeset)
    end

    test "set_now/3 (master override) re-anchors and broadcasts" do
      {story, _gm} = gdr_fixture()
      story = enable_modules(story, [:calendar])
      {:ok, _} = Calendars.save_calendar(story, calendar_attrs(), ~U[2026-01-01 00:00:00Z])
      Calendars.subscribe(story.id)

      later = ~U[2026-03-01 00:00:00Z]

      assert {:ok, config} =
               Calendars.set_now(
                 story,
                 %{
                   "epoch_year" => "2200",
                   "epoch_month" => "2",
                   "epoch_day" => "5",
                   "epoch_hour" => "3",
                   "epoch_minute" => "7"
                 },
                 later
               )

      assert_receive {:calendar_changed, %{id: id}}
      assert id == config.id
      assert config.ratio == 1
      assert %{year: 2200, month: 2, day: 5, hour: 3, minute: 7} = Calendars.now(story, later)
    end

    test "set_now/3 on an unset calendar starts the default one" do
      {story, _gm} = gdr_fixture()
      story = enable_modules(story, [:calendar])

      attrs = %{
        "epoch_year" => "2121",
        "epoch_month" => "12",
        "epoch_day" => "31",
        "epoch_hour" => "23",
        "epoch_minute" => "59"
      }

      assert {:ok, config} = Calendars.set_now(story, attrs)
      assert length(config.month_names) == 12
      assert %{month_name: "December", day: 31} = Calendars.now(story)
    end

    test "new esiti are stamped with the game date when the module is on" do
      {story, _gm} = gdr_fixture()
      story = enable_modules(story, [:esiti])
      user = TannhauserGate.AccountsFixtures.user_fixture()
      character = character_fixture(user, story)
      attrs = %{"character_id" => character.id, "title" => "Look", "body" => "Around"}

      assert {:ok, esito} = Esiti.create_esito(user, story, attrs)
      assert esito.game_date_label == nil

      story = enable_modules(story, [:calendar])
      {:ok, _} = Calendars.save_calendar(story, calendar_attrs())
      {:ok, _} = Esiti.withdraw(user, story, esito)
      assert {:ok, esito} = Esiti.create_esito(user, story, attrs)
      assert esito.game_date_label =~ "Ashfall 2121 AE"
    end
  end

  describe "weather table" do
    test "conditions are validated and scoped to the GDR" do
      {story, _gm} = gdr_fixture()
      {other, _} = gdr_fixture()

      assert {:error, changeset} =
               Weather.create_condition(story, %{"name" => "X", "icon" => "hero-nope"})

      assert %{icon: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Weather.create_condition(story, %{
                 "name" => "X",
                 "icon" => "hero-sun",
                 "weights" => %{"default" => "-1"}
               })

      assert %{weights: [_]} = errors_on(changeset)

      condition =
        condition!(story, "Smog", %{"default" => "3", "Winter" => ""}, %{
          "temp_min" => %{"default" => "4"},
          "temp_max" => %{"default" => "-2"}
        })

      assert condition.weights == %{"default" => 3}
      assert Condition.temperature_range(condition, "Winter") == {-2, 4}
      assert Weather.get_condition(other, condition.id) == nil
      assert Weather.get_condition(story, "nope") == nil
    end

    test "pick/3 is weighted by season with a default fallback" do
      rain = %Condition{name: "Rain", weights: %{"Winter" => 3, "default" => 1}}
      sun = %Condition{name: "Sun", weights: %{"Summer" => 5}}
      none = %Condition{name: "None", weights: %{}}
      table = [rain, none, sun]

      assert Weather.pick(table, "Winter", fn 3 -> 3 end) == rain
      assert Weather.pick(table, "Summer", fn 6 -> 1 end) == rain
      assert Weather.pick(table, "Summer", fn 6 -> 2 end) == sun
      assert Weather.pick(table, "Summer", fn 6 -> 6 end) == sun
      assert Weather.pick([none, sun], "Winter", fn _ -> flunk("no roll") end) == nil

      counts =
        Enum.frequencies(for _ <- 1..600, do: Weather.pick(table, "Summer").name)

      assert counts["Sun"] > counts["Rain"]
      refute Map.has_key?(counts, "None")
    end
  end

  describe "zone weather" do
    setup do
      {story, gm} = gdr_fixture()
      story = enable_modules(story, [:weather])
      %{story: story, gm: gm, docks: zone!(story, "Docks"), spire: zone!(story, "Spire")}
    end

    test "masters set it for one interval, scoped to the GDR", ctx do
      now = ~U[2026-10-25 10:00:00Z]
      {other, _} = gdr_fixture()
      foreign = zone!(other, "Elsewhere")

      assert {:error, :zone_not_found} =
               Weather.set_zone_weather(ctx.story, foreign.id, ctx.gm, %{"condition" => "Fog"})

      assert {:error, %Ecto.Changeset{}} =
               Weather.set_zone_weather(ctx.story, ctx.docks.id, ctx.gm, %{"condition" => ""})

      Weather.subscribe(ctx.story.id)

      assert {:ok, weather} =
               Weather.set_zone_weather(
                 ctx.story,
                 ctx.docks.id,
                 ctx.gm,
                 %{"condition" => "Fog", "icon" => "hero-eye-slash", "temperature" => "4"},
                 now
               )

      assert_receive {:weather_changed, _}
      assert %{set_by: "master", temperature: 4, user_id: user_id} = weather
      assert user_id == ctx.gm.id
      assert weather.expires_at == DateTime.add(now, 6 * 3600)

      assert {:ok, again} =
               Weather.set_zone_weather(ctx.story, ctx.docks.id, ctx.gm, %{"condition" => "Rain"})

      assert again.id == weather.id
      assert Weather.zone_weather(ctx.docks).condition == "Rain"
      assert {:error, :zone_not_found} = Weather.clear_zone_weather(ctx.story, foreign.id)
      assert :ok = Weather.clear_zone_weather(ctx.story, ctx.docks.id)
      assert Weather.zone_weather(ctx.docks) == nil
    end

    test "roll_due/2 rolls due zones and skips locked ones", ctx do
      now = ~U[2026-10-25 10:00:00Z]

      condition!(ctx.story, "Acid rain", %{"default" => "1"}, %{
        "temp_min" => %{"default" => "5"},
        "temp_max" => %{"default" => "5"}
      })

      {:ok, _} =
        Weather.set_zone_weather(ctx.story, ctx.docks.id, ctx.gm, %{"condition" => "Fog"}, now)

      # A GDR with the module off is left alone.
      {off, _} = gdr_fixture()
      off_zone = zone!(off, "Off")
      condition!(off, "Sun", %{"default" => "1"})

      assert Weather.roll_due(DateTime.add(now, 1, :hour)) >= 1
      assert %{condition: "Fog", set_by: "master"} = Weather.zone_weather(ctx.docks)

      assert %{condition: "Acid rain", set_by: "generated", temperature: 5} =
               Weather.zone_weather(ctx.spire)

      assert Weather.zone_weather(off_zone) == nil

      # Nothing is due before the interval ends.
      assert Weather.roll_story_due(ctx.story, DateTime.add(now, 5, :hour)) == 0

      assert Weather.roll_story_due(ctx.story, DateTime.add(now, 6, :hour)) == 1
      assert %{condition: "Acid rain", set_by: "generated"} = Weather.zone_weather(ctx.docks)
      assert Weather.roll_story_due(ctx.story, DateTime.add(now, 7, :hour)) == 1
    end

    test "rolls follow the calendar season", ctx do
      story = enable_modules(ctx.story, [:calendar])

      {:ok, _} =
        Calendars.save_calendar(story, calendar_attrs(), ~U[2026-01-01 00:00:00Z])

      condition!(story, "Snow", %{"Winter" => "1"})
      condition!(story, "Heat", %{"Summer" => "1"})
      assert Weather.seasons(story) == ~w(Winter Summer)

      assert Weather.roll_story_due(story, ~U[2026-01-02 00:00:00Z]) == 2
      assert Weather.zone_weather(ctx.docks).condition == "Snow"

      assert {:ok, %ZoneWeather{condition: "Heat"}} =
               Weather.roll_zone(story, ctx.docks.id, ~U[2026-02-15 00:00:00Z])
    end

    test "nothing rolls without a table or with the module off", ctx do
      assert Weather.roll_story_due(ctx.story) == 0
      assert {:error, :empty_table} = Weather.roll_zone(ctx.story, ctx.docks.id)

      condition!(ctx.story, "Sun", %{"default" => "1"})
      {:ok, story} = TannhauserGate.Stories.set_module_enabled(ctx.story, :weather, false)
      assert Weather.roll_story_due(story) == 0
      assert Repo.aggregate(ZoneWeather, :count) == 0
    end
  end
end
