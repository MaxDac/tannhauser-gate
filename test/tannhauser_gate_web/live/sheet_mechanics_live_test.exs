defmodule TannhauserGateWeb.SheetMechanicsLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Experience, Sheet, Stories, Trackers}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  describe "GM configuration" do
    test "the GDR admin configures creation budgets and XP costs", ctx do
      sheet_item_fixture(ctx.story, %{name: "Strength"})
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/creation")

      assert has_element?(lv, "#formula-keys", "strength")

      lv
      |> form("#category-form-attribute",
        category: %{creation_mode: "points", creation_points: ""}
      )
      |> render_submit()

      assert has_element?(lv, "#category-attribute_creation_points-errors", "required")

      lv
      |> form("#category-form-attribute",
        category: %{
          creation_mode: "points",
          creation_points: "7",
          starting_value: "1",
          xp_cost_formula: "next * 5"
        }
      )
      |> render_submit()

      category = Sheet.categories(ctx.story)["attribute"]
      assert {category.creation_mode, category.creation_points} == {"points", 7}
      assert category.xp_cost_formula == "next * 5"

      lv
      |> form("#category-form-skill", category: %{xp_cost_formula: "next * dexterity"})
      |> render_submit()

      assert has_element?(lv, "#category-form-skill", "dexterity")
    end

    test "the GDR admin defines trackers", ctx do
      sheet_item_fixture(ctx.story, %{name: "Stamina"})
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/trackers")

      lv
      |> form("#tracker-form",
        tracker: %{
          name: "Health",
          max_formula: "stamina + 3",
          damage_types: "superficial, aggravated"
        }
      )
      |> render_submit()

      [tracker] = Trackers.list_trackers(ctx.story)
      assert tracker.damage_types == ["superficial", "aggravated"]
      assert has_element?(lv, "#tracker-#{tracker.id}", "Health")

      lv |> element("#edit-tracker-#{tracker.id}") |> render_click()
      lv |> form("#tracker-form", tracker: %{max_formula: "bogus"}) |> render_submit()
      assert has_element?(lv, "#tracker-form", "bogus")

      lv |> element("#delete-tracker-#{tracker.id}") |> render_click()
      assert Trackers.list_trackers(ctx.story) == []
    end

    test "masters cannot configure the GDR", ctx do
      assert {:error, {_kind, %{to: _}}} =
               live(conn_for(ctx.master), ~p"/g/#{ctx.story}/gm/trackers")
    end
  end

  describe "creation wizard" do
    test "enforces the creation budgets step by step", ctx do
      [str, dex] =
        for name <- ~w(Strength Dexterity),
            do: sheet_item_fixture(ctx.story, %{name: name, min_value: 1, max_value: 5})

      skill =
        sheet_item_fixture(ctx.story, %{
          kind: "skill",
          name: "Firearms",
          min_value: 0,
          max_value: 5
        })

      category_fixture(ctx.story, "attribute", %{
        "creation_mode" => "points",
        "creation_points" => "2",
        "starting_value" => "1"
      })

      conn = conn_for(ctx.player)
      {:ok, lv, _} = live(conn, ~p"/g/#{ctx.story}/characters/new")

      assert has_element?(lv, "#wizard-step-attribute")
      assert has_element?(lv, "#wizard-step-skill")
      refute has_element?(lv, "#wizard-step-power")

      lv |> form("#character-form", character: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#step-errors")
      assert has_element?(lv, "#identity-step:not(.hidden)")

      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()
      assert has_element?(lv, "#budget-attribute", "2")

      lv
      |> form("#character-form", character: %{traits: %{"#{str.id}" => "3", "#{dex.id}" => "3"}})
      |> render_submit()

      assert has_element?(lv, "#step-errors")
      refute has_element?(lv, "#sheet-skill")

      lv
      |> form("#character-form", character: %{traits: %{"#{str.id}" => "2", "#{dex.id}" => "2"}})
      |> render_submit()

      assert has_element?(lv, "#sheet-skill")
      refute has_element?(lv, "#budget-skill")

      lv |> element("#wizard-back") |> render_click()
      assert has_element?(lv, "#trait-#{str.id}[value='2']")

      lv |> form("#character-form") |> render_submit()

      lv
      |> form("#character-form", character: %{traits: %{"#{skill.id}" => "4"}})
      |> render_submit()

      assert has_element?(lv, "#review-step", "Roy")

      {:ok, _show, html} =
        lv |> form("#character-form") |> render_submit() |> follow_redirect(conn)

      assert html =~ "Character created"
      [character] = Characters.list_user_characters(ctx.player)
      assert Characters.trait_values(character) == %{str.id => 2, dex.id => 2, skill.id => 4}
    end

    test "approved owners cannot edit trait values", ctx do
      item = sheet_item_fixture(ctx.story, %{name: "Strength"})
      character = character_fixture(ctx.player, ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}/edit")

      assert has_element?(lv, "#traits-locked")
      refute has_element?(lv, "#trait-#{item.id}")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{character}/edit")
      assert has_element?(lv, "#trait-#{item.id}")
    end
  end

  describe "character sheet" do
    setup ctx do
      strength = sheet_item_fixture(ctx.story, %{name: "Strength", min_value: 1, max_value: 5})
      category_fixture(ctx.story, "attribute", %{"xp_cost_formula" => "next * 2"})

      character =
        character_fixture(ctx.player, ctx.story, %{"traits" => %{"#{strength.id}" => "1"}})

      health =
        tracker_fixture(ctx.story, %{
          "name" => "Health",
          "max_formula" => "strength + 3",
          "damage_types" => "superficial,aggravated"
        })

      humanity =
        tracker_fixture(ctx.story, %{
          "name" => "Humanity",
          "max_formula" => "10",
          "public" => "true"
        })

      %{strength: strength, character: character, health: health, humanity: humanity}
    end

    test "others see only the public trackers and no XP", ctx do
      {:ok, lv, _} =
        live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      assert has_element?(lv, "#tracker-#{ctx.humanity.id}")
      refute has_element?(lv, "#tracker-#{ctx.health.id}")
      refute has_element?(lv, "#experience")
    end

    test "the owner sees trackers and XP and raises items", ctx do
      {:ok, _} = Experience.award(ctx.gm, ctx.character, 10, "First session")
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      assert has_element?(lv, "#tracker-value-#{ctx.health.id}", "4 / 4")
      refute has_element?(lv, "#tracker-edit-#{ctx.health.id}")
      assert has_element?(lv, "#xp-available", "10")
      assert has_element?(lv, "#xp-log", "First session")
      refute has_element?(lv, "#xp-award-form")

      lv |> element("#raise-#{ctx.strength.id}", "4 XP") |> render_click()

      assert has_element?(lv, "#trait-value-#{ctx.strength.id}", "2")
      assert has_element?(lv, "#xp-available", "6")
      assert has_element?(lv, "#xp-log", "Strength: 1 → 2")
      # The tracker max follows the formula.
      assert has_element?(lv, "#tracker-value-#{ctx.health.id}", "5 / 5")
    end

    test "masters edit trackers and award XP", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{ctx.character}")
      refute has_element?(lv, "#raise-#{ctx.strength.id}")

      lv
      |> form("#tracker-edit-#{ctx.health.id}", damage: %{superficial: "1", aggravated: "2"})
      |> render_submit()

      assert has_element?(lv, "#tracker-value-#{ctx.health.id}", "1 / 4")

      lv
      |> form("#tracker-edit-#{ctx.humanity.id}", value: "7")
      |> render_submit()

      assert Trackers.get(ctx.character, ctx.humanity).value == 7

      lv |> form("#xp-award-form", award: %{amount: "5", reason: ""}) |> render_submit()
      assert Experience.totals(ctx.character).earned == 0

      lv |> form("#xp-award-form", award: %{amount: "5", reason: "Good scene"}) |> render_submit()
      assert has_element?(lv, "#xp-earned", "5")
    end
  end

  describe "master dashboard" do
    test "masters award XP and see the log", ctx do
      character = character_fixture(ctx.player, ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/characters")

      assert has_element?(lv, "#xp-#{character.id}", "0 / 0")

      lv
      |> form("#xp-award-form",
        award: %{character_id: character.id, amount: "8", reason: "Chapter one"}
      )
      |> render_submit()

      assert has_element?(lv, "#xp-#{character.id}", "8 / 8")
      assert has_element?(lv, "#story-xp-log", "Chapter one")
    end
  end
end
