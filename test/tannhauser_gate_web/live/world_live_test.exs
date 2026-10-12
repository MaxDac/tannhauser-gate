defmodule TannhauserGateWeb.WorldLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Guide, PeriodicActions, Stories, Trackers, Zones}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    player = user_fixture()
    character = character_fixture(player, story)

    %{story: story, gm: gm, master: master, player: player, character: character}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  describe "guide" do
    test "members read the guide pages from the GDR nav", ctx do
      {:ok, section} = Guide.create_section(ctx.story, %{title: "The world"})

      {:ok, page} =
        Guide.create_page(ctx.story, %{
          section_id: section.id,
          title: "Background",
          body: "# Neo-Meridian\n\nIt **always** rains. <script>alert(1)</script>"
        })

      {:ok, other} =
        Guide.create_page(ctx.story, %{section_id: section.id, title: "Rules", position: 1})

      conn = conn_for(ctx.player)
      {:ok, home, _} = live(conn, ~p"/g/#{ctx.story}")
      assert has_element?(home, "#nav-guide")
      assert has_element?(home, "#gdr-guide-toc-page-#{page.id}")

      assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/g/#{ctx.story}/guide")
      assert to == ~p"/g/#{ctx.story}/guide/#{page}"

      {:ok, lv, html} = live(conn, ~p"/g/#{ctx.story}/guide/#{page}")
      assert has_element?(lv, "#guide-page-title", "Background")
      assert has_element?(lv, "#guide-page-body h1", "Neo-Meridian")
      assert has_element?(lv, "#guide-page-body strong", "always")
      refute html =~ "<script>alert"
      refute has_element?(lv, "#guide-edit-link")

      {:ok, lv, _} =
        lv
        |> element("#guide-toc-page-#{other.id}")
        |> render_click()
        |> follow_redirect(conn)

      assert has_element?(lv, "#guide-page-title", "Rules")
    end

    test "an empty guide says so and is linked from the map", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guide")
      assert has_element?(lv, "#guide-empty")

      {:ok, map, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/map")
      assert has_element?(map, "#map-guide-link")
    end

    test "the GDR admin writes the guide in GM config", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/guide")
      assert has_element?(lv, "#gm-tab-guide")
      assert has_element?(lv, "#guide-sections-empty")

      lv |> form("#section-form", section: %{title: "Lore"}) |> render_submit()
      [section] = Guide.list_sections(ctx.story)
      assert has_element?(lv, "#guide-section-#{section.id}", "Lore")

      lv |> element("#new-page-#{section.id}") |> render_click()

      lv
      |> form("#page-form", page: %{title: "History", body: "## Before the rain"})
      |> render_change()

      assert has_element?(lv, "#page-preview h2", "Before the rain")

      lv
      |> form("#page-form", page: %{title: "History", body: "## Before the rain"})
      |> render_submit()

      assert [%{pages: [page]}] = Guide.list_sections(ctx.story)
      assert page.title == "History"
      assert has_element?(lv, "#guide-page-row-#{page.id}")

      lv |> element("#delete-page-#{page.id}") |> render_click()
      refute has_element?(lv, "#guide-page-row-#{page.id}")

      lv |> element("#delete-section-#{section.id}") |> render_click()
      assert Guide.list_sections(ctx.story) == []
    end

    test "masters and players cannot open the guide editor", ctx do
      assert {:error, {_, %{to: _}}} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/gm/guide")
      assert {:error, {_, %{to: _}}} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/gm/guide")
    end
  end

  describe "zones" do
    test "the GDR admin defines properties, zones and assigns locations", ctx do
      location = location_fixture(ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/zones")

      lv
      |> form("#property-form", property: %{name: "Danger", default_value: "2"})
      |> render_submit()

      [property] = Zones.list_properties(ctx.story)
      assert has_element?(lv, "#zone-property-#{property.id}", "Danger")

      lv
      |> form("#zone-form", zone: %{name: "Docks", values: %{"danger" => "5"}})
      |> render_submit()

      [zone] = Zones.list_zones(ctx.story)
      assert zone.values == %{"danger" => 5}
      assert has_element?(lv, "#zone-#{zone.id}", "Docks")

      {:ok, map, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/map")

      map
      |> element("#location-#{location.id} a", "Edit")
      |> render_click()

      map
      |> form("#location-form", location: %{zone_id: zone.id})
      |> render_submit()

      assert Stories.get_location!(location.id).zone_id == zone.id
      assert has_element?(map, "#location-zone-#{location.id}", "Docks")
    end

    test "masters post zone events that players see in the zone rooms", ctx do
      {:ok, _} = Zones.create_property(ctx.story, %{name: "Danger", default_value: 2})
      {:ok, _} = Zones.create_property(ctx.story, %{name: "Heat", public: false})
      {:ok, zone} = Zones.create_zone(ctx.story, %{name: "Undercity"})
      location = location_fixture(ctx.story, %{zone_id: zone.id})

      {:ok, master_lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      assert has_element?(master_lv, "#master-zones")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/zones")

      lv
      |> form("#zone-event-form",
        event: %{
          zone_id: zone.id,
          title: "Blackout",
          body: "The *lights* go out.",
          happened_on: "2121-03-04"
        }
      )
      |> render_submit()

      [event] = Zones.list_events(zone)
      assert has_element?(lv, "#zone-event-#{event.id}", "Blackout")

      {:ok, room, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{location}")
      assert has_element?(room, "#zone-name", "Undercity")
      assert has_element?(room, "#zone-value-danger", "2")
      refute has_element?(room, "#zone-value-heat")
      assert has_element?(room, "#room-zone-event-#{event.id} em", "lights")

      lv |> element("#delete-zone-event-#{event.id}") |> render_click()
      assert Zones.list_events(zone) == []

      assert {:error, {_, %{to: _}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/zones")
    end
  end

  describe "periodic actions" do
    setup ctx do
      sheet_item_fixture(ctx.story, %{name: "Hunting"})
      tracker_fixture(ctx.story, %{"name" => "Hunger", "max_formula" => "5"})
      {:ok, _} = Trackers.set(ctx.character, "hunger", 4)
      %{location: location_fixture(ctx.story)}
    end

    test "the GDR admin configures periodic actions", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/actions")
      assert has_element?(lv, "#periodic-actions-empty")

      lv
      |> form("#periodic-action-form",
        action: %{
          name: "Hunt",
          items: ["hunting"],
          difficulty_source: "character",
          default_difficulty: "3",
          success_tracker: "hunger",
          success_delta: "-1",
          cooldown_hours: "24"
        }
      )
      |> render_submit()

      [action] = PeriodicActions.list_actions(ctx.story)
      assert action.items == ["hunting"]
      assert action.success_delta == -1
      assert has_element?(lv, "#periodic-action-#{action.id}", "Hunt")

      lv |> element("#delete-periodic-action-#{action.id}") |> render_click()
      assert PeriodicActions.list_actions(ctx.story) == []
    end

    test "players perform an action from a room, masters manage it", ctx do
      {:ok, action} =
        PeriodicActions.create_action(ctx.story, %{
          name: "Hunt",
          items: ["hunting"],
          difficulty_source: "character",
          default_difficulty: 0,
          success_tracker: "hunger",
          success_delta: -1,
          cooldown_hours: 24
        })

      {:ok, room, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      assert has_element?(room, "#action-cooldown-#{action.id}-#{ctx.character.id}", "ready")

      room |> form("#perform-action-#{action.id}") |> render_submit()

      # Difficulty 0: always a success.
      assert has_element?(room, "#action-result", "success")
      assert Trackers.get(ctx.character, "hunger").value == 3
      assert has_element?(room, "#action-cooldown-#{action.id}-#{ctx.character.id}", "ready in")

      room |> form("#perform-action-#{action.id}") |> render_submit()
      assert render(room) =~ "still on cooldown"
      assert Trackers.get(ctx.character, "hunger").value == 3

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/actions")
      [log] = PeriodicActions.list_logs(ctx.story)
      assert has_element?(lv, "#action-log-#{log.id}", ctx.character.name)

      lv
      |> form("#difficulty-form-#{ctx.character.id}", difficulty: "4")
      |> render_submit()

      assert PeriodicActions.character_difficulties(action) == %{ctx.character.id => 4}

      lv |> element("#reset-cooldown-#{ctx.character.id}") |> render_click()
      assert PeriodicActions.cooldown_remaining(action, ctx.character) == 0
      assert has_element?(lv, "#cooldown-#{ctx.character.id}", "ready")

      assert {:error, {_, %{to: _}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/actions")
    end

    test "users without a playable character see no actions", ctx do
      {:ok, _} =
        PeriodicActions.create_action(ctx.story, %{
          name: "Hunt",
          items: ["hunting"],
          difficulty_source: "character"
        })

      {:ok, room, _} = live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      refute has_element?(room, "#room-actions")

      {:ok, room, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      assert has_element?(room, "#room-actions")
    end
  end
end
