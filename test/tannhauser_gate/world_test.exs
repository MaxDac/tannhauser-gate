defmodule TannhauserGate.WorldTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Guide, PeriodicActions, Stories, Trackers, Zones}

  # A deterministic die: returns the given values in order.
  defp dice(values) do
    key = make_ref()
    Process.put(key, values)

    fn _sides ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end

  describe "guide" do
    test "sections hold ordered pages scoped to the story" do
      story = story_fixture()
      other = story_fixture()

      {:ok, rules} = Guide.create_section(story, %{title: "Rules", position: 1})
      {:ok, world} = Guide.create_section(story, %{title: "World", position: 0})

      {:ok, page2} =
        Guide.create_page(story, %{section_id: world.id, title: "Customs", position: 1})

      {:ok, page1} =
        Guide.create_page(story, %{section_id: world.id, title: "History", body: "# Old"})

      {:ok, _} = Guide.create_page(story, %{section_id: rules.id, title: "Combat"})

      assert [%{title: "World", pages: [%{id: id1}, %{id: id2}]}, %{title: "Rules"}] =
               Guide.list_sections(story)

      assert {id1, id2} == {page1.id, page2.id}
      assert Guide.first_page(story).id == page1.id
      assert Guide.first_page(other) == nil
      assert Guide.get_page!(story, page1.id).title == "History"
      assert_raise Ecto.NoResultsError, fn -> Guide.get_page!(other, page1.id) end

      assert {:error, changeset} =
               Guide.create_page(other, %{section_id: world.id, title: "Stolen"})

      assert "is not a section of this guide" in errors_on(changeset).section_id

      assert {:error, changeset} = Guide.update_page(other, page1, %{title: "x"})
      assert errors_on(changeset).section_id == ["is not a section of this guide"]
    end

    test "deleting a section deletes its pages" do
      story = story_fixture()
      {:ok, section} = Guide.create_section(story, %{title: "World"})
      {:ok, page} = Guide.create_page(story, %{section_id: section.id, title: "Page"})

      {:ok, _} = Guide.delete_section(section)
      assert_raise Ecto.NoResultsError, fn -> Guide.get_page!(story, page.id) end
    end

    test "to_html renders Markdown and drops unsafe HTML" do
      html =
        Guide.to_html(
          "# Title\n\n**bold** <script>alert(1)</script> [x](javascript:alert(1)) " <>
            "<img src=x onerror=alert(1)>"
        )

      assert html =~ "<h1>Title</h1>"
      assert html =~ "<strong>bold</strong>"
      refute html =~ "<script"
      refute html =~ "javascript:"
      refute html =~ "onerror"
      assert Guide.to_html(nil) == ""
    end
  end

  describe "zones" do
    setup do
      story = story_fixture()
      {:ok, danger} = Zones.create_property(story, %{name: "Danger", default_value: 2})

      {:ok, secret} =
        Zones.create_property(story, %{name: "Resonance", default_value: 1, public: false})

      %{story: story, danger: danger, secret: secret}
    end

    test "properties get a slug and must be unique", %{story: story, danger: danger} do
      assert danger.slug == "danger"
      assert Zones.property_slugs(story) == ["danger", "resonance"]
      assert {:error, changeset} = Zones.create_property(story, %{name: "Danger"})
      assert errors_on(changeset).slug == ["is already used by another property"]
      assert {:error, changeset} = Zones.create_property(story, %{name: "x", slug: "1bad"})
      assert errors_on(changeset).slug != []
    end

    test "zone values fall back to the property defaults", %{story: story} do
      {:ok, zone} =
        Zones.create_zone(story, %{
          name: "Docks",
          values: %{"danger" => "4", "unknown" => "9"}
        })

      assert zone.values == %{"danger" => 4}
      assert Zones.value(zone, "danger") == 4
      assert Zones.value(zone, "resonance") == 1
      assert Zones.value(zone, "nope") == nil

      assert [{%{slug: "danger"}, 4}, {%{slug: "resonance"}, 1}] = Zones.zone_values(zone)
      assert [{%{slug: "danger"}, 4}] = Zones.zone_values(zone, public_only: true)

      assert {:error, changeset} = Zones.create_zone(story, %{name: "Docks"})
      assert errors_on(changeset).name != []
    end

    test "a location belongs to at most one zone of its story", %{story: story} do
      {:ok, zone} = Zones.create_zone(story, %{name: "Upper"})
      location = location_fixture(story)

      assert {:ok, location} = Stories.update_location(location, %{zone_id: zone.id})
      assert Zones.zone_of(location).id == zone.id
      assert [%{locations: [%{id: id}]}] = Zones.list_zones(story)
      assert id == location.id

      {:ok, foreign} = Zones.create_zone(story_fixture(), %{name: "Elsewhere"})
      assert {:error, changeset} = Stories.update_location(location, %{zone_id: foreign.id})
      assert errors_on(changeset).zone_id == ["is not a zone of this story"]

      {:ok, _} = Zones.delete_zone(zone)
      assert Zones.zone_of(Stories.get_location!(location.id)) == nil
    end

    test "events are posted on a zone and listed newest first", %{story: story} do
      master = user_fixture()
      {:ok, zone} = Zones.create_zone(story, %{name: "Undercity"})

      {:ok, _old} =
        Zones.create_event(zone, master, %{
          title: "Raid",
          body: "Precinct 9 sweeps the docks.",
          happened_on: ~D[2121-01-01]
        })

      {:ok, new} =
        Zones.create_event(zone, master, %{
          title: "Blackout",
          body: "The lights go out.",
          happened_on: ~D[2121-02-01]
        })

      assert [%{title: "Blackout"}, %{title: "Raid"}] = Zones.list_events(zone)
      assert [%{zone: %{name: "Undercity"}} | _] = Zones.list_story_events(story)
      assert Zones.get_event!(story, new.id).id == new.id
      assert_raise Ecto.NoResultsError, fn -> Zones.get_event!(story_fixture(), new.id) end

      assert {:error, changeset} = Zones.create_event(zone, master, %{title: ""})
      assert errors_on(changeset).title != []
    end
  end

  describe "periodic actions" do
    setup do
      story = story_fixture()
      sheet_item_fixture(story, %{name: "Hunting"})
      hunting = Enum.find(TannhauserGate.Sheet.list_items(story), &(&1.slug == "hunting"))
      tracker_fixture(story, %{"name" => "Hunger", "max_formula" => "5"})

      tracker_fixture(story, %{
        "name" => "Health",
        "max_formula" => "7",
        "damage_types" => "superficial,aggravated"
      })

      {:ok, _} = Zones.create_property(story, %{name: "Danger", default_value: 3})
      {:ok, zone} = Zones.create_zone(story, %{name: "Docks", values: %{"danger" => 5}})
      location = location_fixture(story, %{zone_id: zone.id})
      player = user_fixture()

      character =
        character_fixture(player, story, %{"traits" => %{to_string(hunting.id) => "3"}})

      {:ok, _} = Trackers.set(character, "hunger", 3)

      {:ok, action} =
        PeriodicActions.create_action(story, %{
          name: "Hunt",
          items: "hunting",
          difficulty_source: "zone",
          zone_property: "danger",
          success_tracker: "hunger",
          success_delta: -2,
          failure_tracker: "health",
          failure_damage_type: "superficial",
          failure_delta: 1,
          cooldown_hours: 12
        })

      %{story: story, location: location, player: player, character: character, action: action}
    end

    test "validates the items, the zone property and the effects", %{story: story} do
      assert {:error, changeset} =
               PeriodicActions.create_action(story, %{
                 name: "Bad",
                 items: ["nope"],
                 difficulty_source: "zone",
                 success_tracker: "nope",
                 failure_tracker: "health"
               })

      errors = errors_on(changeset)
      assert errors.items != []
      assert errors.zone_property != []
      assert errors.success_tracker == ["is not a tracker"]
      assert errors.failure_damage_type == ["is required for this tracker"]

      assert {:ok, action} =
               PeriodicActions.create_action(story, %{
                 name: "Feed",
                 items: ["hunting", ""],
                 difficulty_source: "character",
                 zone_property: "danger",
                 default_difficulty: 4
               })

      assert action.items == ["hunting"]
      assert action.zone_property == nil
    end

    test "zone difficulty comes from the zone of the location", ctx do
      assert PeriodicActions.difficulty(ctx.action, ctx.character, ctx.location) == 5
      no_zone = location_fixture(ctx.story)
      assert PeriodicActions.difficulty(ctx.action, ctx.character, no_zone) == 1
      assert PeriodicActions.difficulty(ctx.action, ctx.character, nil) == 1
    end

    test "per-character difficulty is set by the masters", ctx do
      {:ok, action} =
        PeriodicActions.update_action(ctx.action, %{
          difficulty_source: "character",
          default_difficulty: 6
        })

      assert PeriodicActions.difficulty(action, ctx.character, ctx.location) == 6
      assert {:ok, _} = PeriodicActions.set_difficulty(action, ctx.character, "8")
      assert PeriodicActions.difficulty(action, ctx.character, ctx.location) == 8
      assert PeriodicActions.character_difficulties(action) == %{ctx.character.id => 8}
      assert {:error, _} = PeriodicActions.set_difficulty(action, ctx.character, "500")
      assert {:ok, nil} = PeriodicActions.set_difficulty(action, ctx.character, "")
      assert PeriodicActions.difficulty(action, ctx.character, ctx.location) == 6
    end

    test "success applies the success effect and starts the cooldown", ctx do
      # 2d6 (3 + 3) + hunting 3 = 9 vs danger 5.
      assert {:ok, log} =
               PeriodicActions.perform(ctx.action, ctx.character, ctx.location,
                 user: ctx.player,
                 rng: dice([3, 3])
               )

      assert log.success
      assert log.difficulty == 5
      assert log.effect == "Hunger -2"
      assert log.user_id == ctx.player.id
      assert log.location.id == ctx.location.id
      assert Trackers.get(ctx.character, "hunger").value == 1

      remaining = PeriodicActions.cooldown_remaining(ctx.action, ctx.character)
      assert remaining > 11 * 3600 and remaining <= 12 * 3600

      assert {:error, :cooldown} =
               PeriodicActions.perform(ctx.action, ctx.character, ctx.location, rng: dice([6, 6]))

      later = DateTime.add(DateTime.utc_now(), 13 * 3600, :second)
      assert PeriodicActions.cooldown_remaining(ctx.action, ctx.character, later) == 0

      assert {:ok, _} = PeriodicActions.reset_cooldown(ctx.action, ctx.character)
      assert PeriodicActions.cooldown_remaining(ctx.action, ctx.character) == 0
      assert [%{counts_for_cooldown: false}] = PeriodicActions.list_logs(ctx.story)
    end

    test "failure applies the failure damage", ctx do
      # 2d6 (1 + 1) + hunting 3 = 5 vs danger 6.
      {:ok, zone} = Zones.create_zone(ctx.story, %{name: "Pit", values: %{"danger" => 6}})
      {:ok, pit} = Stories.update_location(ctx.location, %{zone_id: zone.id})

      assert {:ok, log} =
               PeriodicActions.perform(ctx.action, ctx.character, pit, rng: dice([1, 1]))

      refute log.success
      assert log.effect == "Health +1 superficial"
      assert Trackers.get(ctx.character, "health").damage["superficial"] == 1
      assert Trackers.get(ctx.character, "hunger").value == 3
      assert [%{id: id}] = PeriodicActions.character_logs(ctx.character)
      assert id == log.id
    end

    test "refuses characters and locations of other stories", ctx do
      outsider = character_fixture(user_fixture(), story_fixture())

      assert {:error, :wrong_story} =
               PeriodicActions.perform(ctx.action, outsider, ctx.location)

      assert {:error, :wrong_story} =
               PeriodicActions.perform(ctx.action, ctx.character, location_fixture())

      assert PeriodicActions.error_message(:cooldown) =~ "cooldown"
    end
  end
end
