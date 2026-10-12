defmodule TannhauserGate.SheetMechanicsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Experience, Sheet, Trackers}
  alias TannhauserGate.Sheet.Category

  describe "sheet item slugs" do
    test "derived from the name, unique per GDR and stable on rename" do
      story = story_fixture()
      a = sheet_item_fixture(story, %{name: "Forza Bruta"})
      b = sheet_item_fixture(story, %{name: "Forza bruta"})
      assert a.slug == "forza_bruta"
      assert b.slug == "forza_bruta_2"

      {:ok, renamed} = Sheet.update_item(a, %{name: "Strength"})
      assert renamed.slug == "forza_bruta"
    end

    test "rejects reserved and malformed keys" do
      story = story_fixture()

      for slug <- ["current", "next", "1abc", "has space"] do
        assert {:error, changeset} =
                 Sheet.create_item(story, %{kind: "attribute", name: "X", slug: slug})

        assert errors_on(changeset)[:slug]
      end
    end
  end

  describe "categories" do
    test "default to free entry" do
      categories = Sheet.categories(story_fixture())
      assert categories["attribute"].creation_mode == "free"
      refute Category.budgeted?(categories["skill"])
    end

    test "validate points, distribution and the XP formula" do
      story = story_fixture()
      sheet_item_fixture(story, %{name: "Strength"})

      assert {:error, cs} =
               Sheet.save_category(story, "attribute", %{"creation_mode" => "points"})

      assert errors_on(cs)[:creation_points]

      assert {:error, cs} =
               Sheet.save_category(story, "attribute", %{
                 "creation_mode" => "distribution",
                 "creation_distribution" => "3, x"
               })

      assert errors_on(cs)[:creation_distribution]

      assert {:error, cs} =
               Sheet.save_category(story, "attribute", %{"xp_cost_formula" => "next * agility"})

      assert errors_on(cs)[:xp_cost_formula]

      assert {:ok, category} =
               Sheet.save_category(story, "attribute", %{
                 "creation_mode" => "distribution",
                 "creation_distribution" => "2, 4,3",
                 "xp_cost_formula" => "next * 5 + strength"
               })

      assert category.creation_distribution == "4,3,2"
      assert Sheet.categories(story)["attribute"].id == category.id
    end
  end

  describe "creation budgets" do
    setup do
      story = story_fixture()

      items =
        for name <- ~w(Strength Dexterity Stamina),
            do: sheet_item_fixture(story, %{name: name, min_value: 1, max_value: 5})

      %{story: story, items: items}
    end

    defp traits(items, values),
      do: Map.new(Enum.zip(items, values), fn {item, v} -> {to_string(item.id), to_string(v)} end)

    defp create(story, traits) do
      Characters.create_character(user_fixture(), %{
        "name" => "Budgeted #{System.unique_integer([:positive])}",
        "story_id" => story.id,
        "traits" => traits
      })
    end

    test "points: at most the pool above the starting value", %{story: story, items: items} do
      category_fixture(story, "attribute", %{
        "creation_mode" => "points",
        "creation_points" => "3",
        "starting_value" => "1"
      })

      assert {:error, cs} = create(story, traits(items, [3, 3, 1]))
      assert errors_on(cs)[:traits]

      assert {:error, _} = create(story, traits(items, [0, 1, 1]))

      assert {:ok, character} = create(story, traits(items, [3, 2, 1]))
      assert Map.values(Characters.trait_values(character)) |> Enum.sort() == [1, 2, 3]

      # Missing values get the starting value.
      assert {:ok, character} = create(story, %{})
      assert Map.values(Characters.trait_values(character)) == [1, 1, 1]
    end

    test "distribution: the listed values exactly", %{story: story, items: items} do
      category_fixture(story, "attribute", %{
        "creation_mode" => "distribution",
        "creation_distribution" => "3,2",
        "starting_value" => "1"
      })

      status = Sheet.budget_status(Sheet.categories(story)["attribute"], items, %{})
      refute status.ok?
      assert status.missing == [3, 2]

      assert {:error, _} = create(story, traits(items, [3, 3, 1]))
      assert {:ok, _} = create(story, traits(items, [1, 3, 2]))
    end

    test "masters and NPCs ignore the budgets", %{story: story, items: items} do
      category_fixture(story, "attribute", %{
        "creation_mode" => "points",
        "creation_points" => "0"
      })

      {story, gm} = {story, admin_fixture()}

      assert {:ok, npc} =
               Characters.create_npc(gm, story, %{
                 "name" => "Boss",
                 "traits" => traits(items, [5, 5, 5])
               })

      assert Characters.trait_values(npc) |> Map.values() == [5, 5, 5]

      {:error, _} = create(story, traits(items, [2, 1, 1]))
      {:ok, character} = create(story, traits(items, [1, 1, 1]))

      assert {:ok, _} =
               Characters.update_character(
                 character,
                 %{"traits" => traits(items, [5, 5, 5])},
                 nil,
                 master?: true
               )

      assert Characters.trait_values(character) |> Map.values() == [5, 5, 5]
    end

    test "approved owners cannot edit trait values", %{story: story, items: [strength | _]} do
      character = character_fixture(nil, story)

      {:ok, _} =
        Characters.update_character(
          character,
          %{"traits" => %{to_string(strength.id) => "5"}},
          nil
        )

      refute Characters.trait_values(character)[strength.id] == 5
    end
  end

  describe "trackers" do
    setup do
      story = story_fixture()
      stamina = sheet_item_fixture(story, %{name: "Stamina", min_value: 1, max_value: 5})
      character = character_fixture(nil, story, %{"traits" => %{to_string(stamina.id) => "2"}})
      %{story: story, character: character}
    end

    test "validates the max formula against the item keys", %{story: story} do
      assert {:error, cs} =
               Trackers.create_tracker(story, %{"name" => "Health", "max_formula" => "next + 3"})

      assert errors_on(cs)[:max_formula]

      assert {:ok, tracker} =
               Trackers.create_tracker(story, %{
                 "name" => "Health",
                 "max_formula" => "stamina + 3",
                 "damage_types" => "superficial, aggravated"
               })

      assert tracker.slug == "health"
      assert tracker.damage_types == ["superficial", "aggravated"]
      refute tracker.public
    end

    test "simple trackers: adjust and set, clamped", %{story: story, character: character} do
      tracker_fixture(story, %{"name" => "Willpower", "max_formula" => "stamina + 1"})

      state = Trackers.get(character, "willpower")
      assert state.max == 3
      assert state.value == 3

      assert {:ok, %{value: 1}} = Trackers.adjust(character, "willpower", -2)
      assert {:ok, %{value: 0}} = Trackers.adjust(character, "willpower", -5)
      assert {:ok, %{value: 3}} = Trackers.set(character, "willpower", 99)
      assert {:error, :simple_tracker} = Trackers.adjust(character, "willpower", {"x", 1})
      assert {:error, :not_found} = Trackers.adjust(character, "nope", 1)
    end

    test "damage trackers", %{story: story, character: character} do
      tracker =
        tracker_fixture(story, %{
          "name" => "Health",
          "max_formula" => "stamina + 3",
          "damage_types" => "superficial,aggravated"
        })

      assert {:ok, state} = Trackers.adjust(character, tracker, {"superficial", 2})
      assert state.value == 3
      assert {:ok, state} = Trackers.set_damage(character, tracker.id, "aggravated", 9)
      assert state.damage == %{"superficial" => 2, "aggravated" => 3}
      assert state.value == 0
      assert {:error, :invalid_damage_type} = Trackers.adjust(character, tracker, {"fire", 1})
      assert {:error, :damage_tracker} = Trackers.set(character, tracker, 1)
    end

    test "public_only hides private trackers", %{story: story, character: character} do
      tracker_fixture(story, %{"name" => "Hunger"})
      tracker_fixture(story, %{"name" => "Humanity", "public" => "true"})

      assert Trackers.character_trackers(character) |> length() == 2

      assert [%{tracker: %{name: "Humanity"}}] =
               Trackers.character_trackers(character, public_only: true)
    end
  end

  describe "experience" do
    setup do
      {story, gm} = gdr_fixture()
      strength = sheet_item_fixture(story, %{name: "Strength", min_value: 1, max_value: 3})
      user = user_fixture()
      character = character_fixture(user, story, %{"traits" => %{to_string(strength.id) => "1"}})
      category_fixture(story, "attribute", %{"xp_cost_formula" => "next * 5"})
      %{story: story, gm: gm, user: user, character: character, strength: strength}
    end

    test "masters award XP with a reason", %{gm: gm, user: user, character: character} do
      assert {:error, :unauthorized} = Experience.award(user, character, 5, "nope")
      assert {:error, :reason_required} = Experience.award(gm, character, 5, " ")
      assert {:error, :invalid_amount} = Experience.award(gm, character, "0", "x")
      assert {:error, :invalid_amount} = Experience.award(gm, character, "abc", "x")
      assert {:ok, _} = Experience.award(gm, character, "12", "Great session")
      assert {:error, :insufficient_xp} = Experience.award(gm, character, -13, "Too much")
      assert {:ok, _} = Experience.award(gm, character, -2, "Correction")

      assert Experience.totals(character) == %{earned: 10, spent: 0, available: 10}

      assert [%{amount: -2}, %{amount: 12, reason: "Great session"}] =
               Experience.list_entries(character)
    end

    test "owners spend XP to raise items", ctx do
      %{gm: gm, user: user, character: character, strength: strength} = ctx

      assert Experience.cost(character, strength) == {:ok, 10}
      assert {:error, :insufficient_xp} = Experience.spend(user, character, strength.id)

      {:ok, _} = Experience.award(gm, character, 30, "Story arc")
      assert {:error, :unauthorized} = Experience.spend(gm, character, strength.id)

      assert {:ok, entry} = Experience.spend(user, character, to_string(strength.id))
      assert {entry.from_value, entry.to_value, entry.amount} == {1, 2, 10}
      assert Characters.trait_values(character)[strength.id] == 2

      assert {:ok, _} = Experience.spend(user, character, strength.id)
      assert {:error, :at_max} = Experience.spend(user, character, strength.id)
      assert Experience.totals(character) == %{earned: 30, spent: 25, available: 5}
      assert %{available: 5} = Experience.totals_by_character(character.story_id)[character.id]
    end

    test "items without a cost formula cannot be bought", ctx do
      skill = sheet_item_fixture(ctx.story, %{kind: "skill", name: "Firearms"})
      {:ok, _} = Experience.award(ctx.gm, ctx.character, 30, "Story arc")
      assert {:error, :not_purchasable} = Experience.spend(ctx.user, ctx.character, skill.id)
    end

    test "only playable characters spend XP", ctx do
      draft = draft_character_fixture(nil, ctx.story)
      assert {:error, :cannot_play} = Experience.spend(draft.user, draft, ctx.strength.id)
    end
  end
end
