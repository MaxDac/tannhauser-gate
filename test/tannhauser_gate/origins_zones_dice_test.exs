defmodule TannhauserGate.OriginsZonesDiceTest do
  use TannhauserGate.DataCase, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Dice
  alias TannhauserGate.Dice.Config
  alias TannhauserGate.Origins
  alias TannhauserGate.Trackers
  alias TannhauserGate.Zones
  alias TannhauserGateWeb.{EsitiComponents, GameComponents, GuildComponents}

  defp failed_pool_result do
    %{
      "system" => "pool",
      "difficulty" => nil,
      "dice" => [%{"value" => 1, "special" => false, "success" => false}]
    }
  end

  describe "origins" do
    setup do
      {story, _gm} = gdr_fixture()
      story = enable_modules(story, [:origins])
      body = sheet_item_fixture(story, %{name: "Body"})
      {:ok, group} = Origins.create_group(story, %{name: "Origin"})
      {:ok, human} = Origins.create_option(story, %{group_id: group.id, name: "Human"})
      character = character_fixture(user_fixture(), story)
      %{story: story, body: body, group: group, human: human, character: character}
    end

    test "enabled? accepts story ids and rejects anything else", %{story: story} do
      assert Origins.enabled?(story.id)
      refute Origins.enabled?(nil)
      refute Origins.enabled?("nope")
    end

    test "options can be created with an image and have it removed", ctx do
      assert {:ok, option} =
               Origins.create_option(
                 ctx.story,
                 %{group_id: ctx.group.id, name: "Android"},
                 "/uploads/android.png"
               )

      assert option.image_path == "/uploads/android.png"
      assert {:ok, option} = Origins.remove_option_image(option)
      assert option.image_path == nil
    end

    test "unsaved characters have no origins, choices or bonuses", %{story: story} do
      character = %Character{id: nil, story_id: story.id}

      assert Origins.character_origins(character) == []
      assert Origins.choices(character) == %{}
      assert Origins.bonuses(character) == %{}
    end

    test "normalize_choices handles blank, integer and invalid values", ctx do
      groups = Origins.list_groups(ctx.story)
      group_id = ctx.group.id

      assert Origins.normalize_choices(groups, "nope") == {:error, "Invalid origins"}
      assert Origins.normalize_choices(groups, %{group_id => nil}) == {:ok, %{group_id => nil}}

      assert Origins.normalize_choices(groups, %{to_string(group_id) => "  "}) ==
               {:ok, %{group_id => nil}}

      assert Origins.normalize_choices(groups, %{group_id => ctx.human.id}) ==
               {:ok, %{group_id => ctx.human.id}}

      assert {:error, "Origin: choose one of its options"} =
               Origins.normalize_choices(groups, %{group_id => "abc"})

      assert {:error, "Origin: choose one of its options"} =
               Origins.normalize_choices(groups, %{group_id => 1.5})

      assert {:error, "Unknown origin group"} =
               Origins.normalize_choices(groups, %{"x" => ctx.human.id})
    end

    test "save_choices reports invalid choices", ctx do
      assert {:error, "Origin: choose one of its options"} =
               Origins.save_choices(ctx.character, %{ctx.group.id => "abc"})

      assert {:ok, 1} = Origins.save_choices(ctx.character, %{ctx.group.id => ctx.human.id})
      assert Origins.choices(ctx.character) == %{ctx.group.id => ctx.human.id}
    end

    test "sum_bonuses skips non integer values and signed handles zero" do
      assert Origins.sum_bonuses([%{"body" => 1, "mind" => "2"}, nil, %{"body" => 2}]) ==
               %{"body" => 3}

      assert Origins.signed(0) == "0"
    end
  end

  describe "zones" do
    setup do
      {story, _gm} = gdr_fixture()
      %{story: story}
    end

    test "properties can be fetched, updated and deleted", %{story: story} do
      {:ok, property} = Zones.create_property(story, %{name: "Danger"})

      fetched = Zones.get_property!(story, property.id)
      assert fetched.slug == "danger"

      assert {:ok, updated} = Zones.update_property(fetched, %{default_value: 3})
      assert updated.default_value == 3

      assert {:error, changeset} = Zones.update_property(updated, %{slug: "1bad"})

      assert "must start with a letter and use only lowercase letters, digits and _" in errors_on(
               changeset
             ).slug

      assert {:ok, _} = Zones.delete_property(updated)
      assert Zones.list_properties(story) == []
    end

    test "zones can be fetched and updated", %{story: story} do
      {:ok, _} = Zones.create_property(story, %{name: "Danger"})
      {:ok, zone} = Zones.create_zone(story, %{name: "Docks"})

      fetched = Zones.get_zone!(story, zone.id)
      assert fetched.name == "Docks"

      assert {:ok, updated} =
               Zones.update_zone(fetched, %{name: "Old docks", values: %{"danger" => "4"}})

      assert updated.name == "Old docks"
      assert Zones.value(updated, "danger") == 4

      {other, _gm} = gdr_fixture()
      assert_raise Ecto.NoResultsError, fn -> Zones.get_zone!(other, zone.id) end
    end
  end

  describe "dice" do
    setup do
      {story, _gm} = gdr_fixture()
      tracker_fixture(story, %{"name" => "Willpower", "max_formula" => "3"})
      sheet_item_fixture(story, %{name: "Body"})
      tracker_fixture(story, %{"name" => "Broken", "max_formula" => "5 / body"})
      character = character_fixture(user_fixture(), story)
      %{story: story, character: character}
    end

    test "roll and reroll work with the story defaults", %{character: character} do
      assert {:ok, %{"summary" => summary}} = Dice.roll(character, %{})
      assert is_binary(summary)

      assert {:error, :no_reroll} = Dice.reroll(character, failed_pool_result())
    end

    test "rolling with an unknown system fails", %{character: character} do
      assert {:error, "Unknown dice system."} =
               Dice.roll(character, %{}, config: %Config{system: "tarot"})
    end

    test "pool rolls ignore an unknown special tracker", %{character: character} do
      config = %Config{system: "pool", special_tracker: "missing"}

      assert {:ok, %{"special_count" => 0}} =
               Dice.roll(character, %{"modifier" => 2}, config: config, rng: fn _ -> 1 end)
    end

    test "reroll errors", %{character: character} do
      config = %Config{system: "pool", reroll_tracker: "willpower"}

      assert {:error, :no_reroll} =
               Dice.reroll(character, failed_pool_result(), nil,
                 config: %{config | reroll_max_dice: 0}
               )

      assert {:error, :not_a_pool} =
               Dice.reroll(character, %{"system" => "d20"}, nil, config: config)

      assert {:error, :not_a_pool} = Dice.reroll(character, %{}, nil, config: config)

      assert {:error, :not_found} =
               Dice.reroll(character, failed_pool_result(), nil,
                 config: %{config | reroll_tracker: "nope"}
               )

      assert {:error, :not_enough} =
               Dice.reroll(character, failed_pool_result(), nil,
                 config: %{config | reroll_tracker: "broken"}
               )

      assert Trackers.get(character, "broken").error =~ "Invalid maximum"
    end

    test "error messages" do
      for reason <- [
            :unknown_item,
            :no_reroll,
            :not_a_pool,
            :already_rerolled,
            :nothing_to_reroll,
            :invalid_dice,
            :not_enough,
            :unauthorized
          ] do
        assert is_binary(Dice.error_message(reason))
      end

      assert Dice.error_message("Custom") == "Custom"
      assert is_binary(Dice.error_message(:not_found))
    end

    test "parse_expression rejects out of range input" do
      assert Dice.parse_expression(nil) == {:error, "is empty"}
      assert {:error, "dice need 2 to " <> _} = Dice.parse_expression("1d1")
      assert {:error, "dice need 2 to " <> _} = Dice.parse_expression("1d100000")
      assert {:error, "numbers cannot exceed " <> _} = Dice.parse_expression("1d6+100000")
    end

    test "summary of an unknown result is empty" do
      assert Dice.summary(%{}) == ""
    end
  end

  describe "dice config" do
    test "exposes systems and crit rules" do
      assert "pool" in Config.systems()
      assert "pairs" in Config.crit_rules()
    end

    test "validates the threshold and the default expression" do
      changeset =
        Config.changeset(%Config{}, %{
          "system" => "pool",
          "die_size" => "6",
          "success_threshold" => "8",
          "crit_rule" => "none",
          "default_expression" => "abc"
        })

      errors = errors_on(changeset)
      assert "cannot be higher than the die size" in errors.success_threshold
      assert errors.default_expression != []
    end
  end

  describe "components" do
    test "guild_emblem renders the emblem image" do
      html =
        render_component(&GuildComponents.guild_emblem/1,
          guild: %{name: "Tyrell", emblem_path: "/uploads/tyrell.png"},
          id: "emblem"
        )

      assert html =~ ~s(src="/uploads/tyrell.png")
      assert html =~ "Emblem of Tyrell"
    end

    test "avatar renders the avatar image" do
      html =
        render_component(&GameComponents.avatar/1,
          character: %{name: "Deckard", avatar_path: "/uploads/deckard.png"}
        )

      assert html =~ ~s(src="/uploads/deckard.png")
    end

    test "the map nav link is active on rooms and stories" do
      for path <- ["/map", "/rooms/1", "/stories/2", "/forum"] do
        assigns = %{path: path}

        html =
          rendered_to_string(~H"""
          <GameComponents.nav_link navigate="/map" icon="hero-map" current_path={@path}>
            Map
          </GameComponents.nav_link>
          """)

        assert String.contains?(html, "bg-phosphor/15") == (path != "/forum")
      end
    end

    test "format_time handles nil" do
      assert GameComponents.format_time(nil) == ""
    end

    test "esiti place and when labels" do
      assert EsitiComponents.place(%{location: %{name: "Bar"}, zone: %{name: "Docks"}}) == "Bar"
      assert EsitiComponents.place(%{location: nil, zone: %{name: "Docks"}}) == "Docks"
      assert EsitiComponents.place(%{location: nil, zone: nil}) == nil
      assert EsitiComponents.when_label(nil) == ""
    end
  end
end
