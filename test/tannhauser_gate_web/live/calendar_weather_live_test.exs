defmodule TannhauserGateWeb.CalendarWeatherLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Calendars, Stories, Weather, Zones}
  alias TannhauserGate.Calendar, as: GameCalendar

  @calendar %{
    "months_text" => "Ashfall | 30 | Winter\nNeonbloom | 30 | Summer",
    "weekdays_text" => "",
    "ratio" => "1",
    "year_suffix" => "AE",
    "epoch_year" => "2121",
    "epoch_month" => "1",
    "epoch_day" => "1",
    "epoch_hour" => "12",
    "epoch_minute" => "0"
  }

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp zone!(story, name) do
    {:ok, zone} = Zones.create_zone(story, %{name: name})
    zone
  end

  defp with_modules(ctx) do
    story = enable_modules(ctx.story, [:calendar, :weather])
    {:ok, _} = Calendars.save_calendar(story, @calendar)
    zone = zone!(story, "Undercity")
    room = location_fixture(story, %{name: "Docks", zone_id: zone.id})
    Map.merge(ctx, %{story: story, zone: zone, room: room})
  end

  describe "modules disabled" do
    test "pages redirect and displays are hidden", ctx do
      zone = zone!(ctx.story, "Undercity")
      room = location_fixture(ctx.story, %{zone_id: zone.id})

      for path <- [
            ~p"/g/#{ctx.story}/gm/calendar",
            ~p"/g/#{ctx.story}/gm/weather",
            ~p"/g/#{ctx.story}/master/calendar",
            ~p"/g/#{ctx.story}/master/weather"
          ] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.gm), path)
        assert to == ~p"/g/#{ctx.story}"
      end

      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/master")
      refute has_element?(lv, "#master-calendar")
      refute has_element?(lv, "#master-weather")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{room}")
      refute has_element?(lv, "#drawer-game-clock")
      refute has_element?(lv, "#room-game-clock")
      refute has_element?(lv, "#room-weather")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/map")
      refute has_element?(lv, "#map-weather")
    end
  end

  describe "authorization" do
    setup :with_modules

    test "players can't open master or GM pages, masters can't open GM tabs", ctx do
      for path <- [
            ~p"/g/#{ctx.story}/gm/calendar",
            ~p"/g/#{ctx.story}/gm/weather",
            ~p"/g/#{ctx.story}/master/calendar",
            ~p"/g/#{ctx.story}/master/weather"
          ] do
        assert {:error, {:redirect, _}} = live(conn_for(ctx.player), path)
      end

      for path <- [~p"/g/#{ctx.story}/gm/calendar", ~p"/g/#{ctx.story}/gm/weather"] do
        assert {:error, {:redirect, _}} = live(conn_for(ctx.master), path)
      end

      assert {:ok, _, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/calendar")
      assert {:ok, _, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/weather")
    end
  end

  describe "calendar" do
    test "the GM configures the calendar", ctx do
      story = enable_modules(ctx.story, [:calendar])
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{story}/gm/calendar")
      assert has_element?(lv, "#gm-tab-calendar")
      assert has_element?(lv, "#calendar-unsaved")

      lv |> form("#calendar-form", config: %{months_text: "Bad | x"}) |> render_change()
      assert has_element?(lv, "#calendar-form .text-error")

      lv |> form("#calendar-form", config: @calendar) |> render_submit()
      refute has_element?(lv, "#calendar-unsaved")
      assert has_element?(lv, "#gm-calendar-clock", "Ashfall 2121 AE")
      assert Calendars.get_calendar(story).month_names == ~w(Ashfall Neonbloom)
    end

    test "masters override the current date and clocks appear", ctx do
      ctx = with_modules(ctx)
      {:ok, room_lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")
      assert has_element?(room_lv, "#drawer-game-clock", "Ashfall 2121")
      assert has_element?(room_lv, "#room-game-clock", "Ashfall 2121")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/calendar")
      assert has_element?(lv, "#master-calendar-clock")

      lv
      |> form("#calendar-date-form",
        date: %{epoch_year: "2199", epoch_month: "2", epoch_day: "7", epoch_hour: "8"}
      )
      |> render_submit()

      assert %{year: 2199, month: 2, day: 7, hour: 8} = Calendars.now(ctx.story)
      # Clocks are phx-update="ignore": the hook redraws them from the data attributes.
      minutes = ctx.story |> Calendars.get_calendar() |> GameCalendar.epoch_minutes()
      assert has_element?(lv, "#master-calendar-clock[data-epoch-minutes='#{minutes}']")
      # Open pages follow the change through PubSub.
      assert has_element?(room_lv, "#room-game-clock[data-epoch-minutes='#{minutes}']")
      assert has_element?(room_lv, "#drawer-game-clock[data-epoch-minutes='#{minutes}']")
      {:ok, room_lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")
      assert has_element?(room_lv, "#room-game-clock", "7 Neonbloom 2199 AE")
    end

    test "game dates are prefilled when the module is on", ctx do
      ctx = with_modules(ctx)
      story = enable_modules(ctx.story, [:diary, :quests])
      owner = user_fixture()
      character = character_fixture(owner, story)

      {:ok, lv, _} = live(conn_for(owner), ~p"/g/#{story}/characters/#{character}/diary")
      lv |> element("#diary-new-entry") |> render_click()

      assert has_element?(
               lv,
               "#diary-form input[name$='[game_date_label]'][value*='Ashfall 2121 AE']"
             )

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{story}/master/zones")

      assert has_element?(
               lv,
               "#zone-event-form input[name$='[game_date_label]'][value*='Ashfall 2121 AE']"
             )

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{story}/master/quests")

      assert has_element?(
               lv,
               "#quest-form input[name$='[game_date_label]'][value*='Ashfall 2121 AE']"
             )
    end

    test "the in-game date field is hidden without the calendar", ctx do
      story = enable_modules(ctx.story, [:quests])
      zone!(story, "Undercity")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{story}/master/zones")
      refute has_element?(lv, "#zone-event-form input[name$='[game_date_label]']")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{story}/master/quests")
      refute has_element?(lv, "#quest-form input[name$='[game_date_label]']")
    end
  end

  describe "weather" do
    setup :with_modules

    test "the GM manages the weather table and the interval", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/weather")
      assert has_element?(lv, "#weather-empty")

      lv
      |> form("#weather-condition-form",
        condition: %{
          name: "Acid rain",
          icon: "hero-cloud-arrow-down",
          weights: %{"Winter" => "4", "Summer" => "1"}
        }
      )
      |> render_submit()

      assert [condition] = Weather.list_conditions(ctx.story)
      assert condition.weights == %{"Winter" => 4, "Summer" => 1}
      assert has_element?(lv, "#weather-condition-#{condition.id}", "Acid rain")

      lv |> element("#delete-weather-condition-#{condition.id}") |> render_click()
      assert Weather.list_conditions(ctx.story) == []

      lv
      |> form("#weather-interval-form", settings: %{weather_interval_hours: "12"})
      |> render_submit()

      assert Stories.get_story!(ctx.story.id).weather_interval_hours == 12
    end

    test "masters set, roll and clear the zone weather; displays update", ctx do
      {:ok, _} =
        Weather.create_condition(ctx.story, %{
          "name" => "Smog",
          "icon" => "hero-eye-slash",
          "weights" => %{"default" => "1"}
        })

      {:ok, room_lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")
      refute has_element?(room_lv, "#room-weather")
      {:ok, map_lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/map")
      assert has_element?(map_lv, "#map-weather-zone-#{ctx.zone.id}", "Unknown")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/weather")

      lv
      |> form("#zone-weather-form",
        weather: %{zone_id: ctx.zone.id, condition: "Neon drizzle", temperature: "9"}
      )
      |> render_submit()

      assert has_element?(lv, "#zone-weather-#{ctx.zone.id}", "Neon drizzle")
      assert has_element?(room_lv, "#room-weather", "Neon drizzle")
      assert has_element?(map_lv, "#map-weather-badge-#{ctx.zone.id}", "Neon drizzle")
      assert has_element?(map_lv, "#room-weather-#{ctx.room.id}")

      lv |> element("#roll-weather-#{ctx.zone.id}") |> render_click()
      assert has_element?(lv, "#zone-weather-#{ctx.zone.id}", "Smog")
      assert has_element?(room_lv, "#room-weather", "Smog")

      lv |> element("#clear-weather-#{ctx.zone.id}") |> render_click()
      refute has_element?(room_lv, "#room-weather")
      assert Weather.zone_weather(ctx.zone) == nil
    end

    test "zones of other GDRs are rejected", ctx do
      {other, _} = gdr_fixture()
      foreign = zone!(other, "Elsewhere")
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/weather")

      render_submit(lv, "set", %{"weather" => %{"zone_id" => foreign.id, "condition" => "Fog"}})
      render_click(lv, "roll", %{"zone" => foreign.id})
      render_click(lv, "clear", %{"zone" => foreign.id})
      assert Weather.zone_weather(foreign) == nil
      assert Weather.zone_weathers(ctx.story) == %{}
    end
  end
end
