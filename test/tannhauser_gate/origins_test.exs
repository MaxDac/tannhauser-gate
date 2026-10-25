defmodule TannhauserGate.OriginsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Dice, Origins, Stories, Trackers}
  alias TannhauserGate.Dice.Config

  setup do
    {story, gm} = gdr_fixture()
    story = enable_modules(story, [:origins])
    body = sheet_item_fixture(story, %{name: "Body"})
    empathy = sheet_item_fixture(story, %{name: "Empathy"})
    {:ok, group} = Origins.create_group(story, %{name: "Origin", required: true})

    {:ok, human} = Origins.create_option(story, %{group_id: group.id, name: "Human"})

    {:ok, replicant} =
      Origins.create_option(story, %{
        "group_id" => group.id,
        "name" => "Replicant",
        "requires_approval" => "true",
        "bonuses" => %{"body" => "1", "empathy" => "-1", "mind" => ""}
      })

    %{
      story: story,
      gm: gm,
      body: body,
      empathy: empathy,
      group: group,
      human: human,
      replicant: replicant
    }
  end

  defp origins(group, option), do: %{to_string(group.id) => to_string(option.id)}

  describe "groups and options" do
    test "CRUD", %{story: story, group: group, human: human, replicant: replicant} do
      assert [%{id: id, options: options}] = Origins.list_groups(story)
      assert id == group.id
      assert Enum.map(options, & &1.id) == [human.id, replicant.id]
      assert replicant.bonuses == %{"body" => 1, "empathy" => -1}
      assert replicant.requires_approval

      {:ok, group} = Origins.update_group(group, %{name: "Lineage"})
      assert group.name == "Lineage"

      {:ok, human} = Origins.update_option(story, human, %{"description" => "**Flesh**"})
      assert human.description == "**Flesh**"

      {:ok, _} = Origins.delete_option(human)
      assert [%{options: [_]}] = Origins.list_groups(story)

      {:ok, _} = Origins.delete_group(group)
      assert Origins.list_groups(story) == []
    end

    test "bonuses must reference sheet items with whole numbers", %{story: story, group: group} do
      assert {:error, cs} =
               Origins.create_option(story, %{
                 group_id: group.id,
                 name: "Bad",
                 bonuses: %{"nope" => 1}
               })

      assert "references unknown sheet item nope" in errors_on(cs).bonuses

      assert {:error, cs} =
               Origins.create_option(story, %{
                 group_id: group.id,
                 name: "Bad",
                 bonuses: %{"body" => "x"}
               })

      assert "body must be a whole number" in errors_on(cs).bonuses

      assert {:error, cs} =
               Origins.create_option(story, %{
                 group_id: group.id,
                 name: "Bad",
                 bonuses: %{"body" => 99}
               })

      assert errors_on(cs).bonuses != []

      assert {:ok, option} =
               Origins.create_option(story, %{
                 group_id: group.id,
                 name: "Zero",
                 bonuses: %{"body" => 0}
               })

      assert option.bonuses == %{}
    end

    test "options cannot use groups or be read from another GDR", %{group: group, human: human} do
      {other, _gm} = gdr_fixture()

      assert {:error, cs} = Origins.create_option(other, %{group_id: group.id, name: "Spy"})
      assert errors_on(cs).group_id == ["is not an origin group of this GDR"]

      assert_raise Ecto.NoResultsError, fn -> Origins.get_option!(other, human.id) end
      assert_raise Ecto.NoResultsError, fn -> Origins.get_group!(other, group.id) end
    end
  end

  describe "character choices" do
    test "players pick one option per group at creation", ctx do
      character =
        draft_character_fixture(nil, ctx.story, %{"origins" => origins(ctx.group, ctx.replicant)})

      assert Origins.choices(character) == %{ctx.group.id => ctx.replicant.id}

      assert [%{group: %{id: group_id}, option: %{id: option_id}}] =
               Origins.character_origins(character)

      assert {group_id, option_id} == {ctx.group.id, ctx.replicant.id}
      assert Origins.requires_approval?(character)

      # Changing the choice replaces it (one per group).
      {:ok, _} =
        Characters.update_character(character, %{"origins" => origins(ctx.group, ctx.human)})

      assert Origins.choices(character) == %{ctx.group.id => ctx.human.id}
      refute Origins.requires_approval?(character)
    end

    test "options of another group or GDR are rejected", ctx do
      {other, _} = gdr_fixture()
      other = enable_modules(other, [:origins])
      {:ok, other_group} = Origins.create_group(other, %{name: "Class"})
      {:ok, spy} = Origins.create_option(other, %{group_id: other_group.id, name: "Spy"})

      character = draft_character_fixture(nil, ctx.story)

      assert {:error, cs} =
               Characters.update_character(character, %{"origins" => origins(ctx.group, spy)})

      assert errors_on(cs).origins != []

      assert {:error, cs} =
               Characters.update_character(character, %{
                 "origins" => origins(other_group, ctx.human)
               })

      assert errors_on(cs).origins != []
      assert Origins.choices(character) == %{}
    end

    test "owners change origins only until approval, masters always", ctx do
      character =
        character_fixture(nil, ctx.story, %{"origins" => origins(ctx.group, ctx.human)})

      assert {:ok, _} =
               Characters.update_character(character, %{
                 "origins" => origins(ctx.group, ctx.replicant)
               })

      assert Origins.choices(character) == %{ctx.group.id => ctx.human.id}

      assert {:ok, _} =
               Characters.update_character(
                 character,
                 %{"origins" => origins(ctx.group, ctx.replicant)},
                 nil,
                 master?: true
               )

      assert Origins.choices(character) == %{ctx.group.id => ctx.replicant.id}
    end

    test "required groups must be chosen before submitting", ctx do
      character = draft_character_fixture(nil, ctx.story)
      assert [%{id: id}] = Origins.missing_required(character)
      assert id == ctx.group.id

      assert {:error, :origins_missing} = Characters.submit_for_approval(character)

      {:ok, _} =
        Characters.update_character(character, %{"origins" => origins(ctx.group, ctx.human)})

      assert {:ok, %{approval_status: "submitted"}} =
               Characters.submit_for_approval(character)
    end

    test "NPCs get origins from masters", ctx do
      {:ok, master} = Stories.add_master(ctx.story, user_fixture().username)

      npc =
        npc_fixture(master, ctx.story, %{"origins" => origins(ctx.group, ctx.replicant)})

      assert Origins.choices(npc) == %{ctx.group.id => ctx.replicant.id}
    end
  end

  describe "effective values" do
    setup ctx do
      character =
        character_fixture(user_fixture(), ctx.story, %{
          "traits" => %{to_string(ctx.body.id) => "3", to_string(ctx.empathy.id) => "2"},
          "origins" => origins(ctx.group, ctx.replicant)
        })

      %{character: character}
    end

    test "bonuses are added to the formula values", %{character: character} do
      assert Origins.bonuses(character) == %{"body" => 1, "empathy" => -1}
      assert %{"body" => 4, "empathy" => 1} = Characters.values_by_slug(character)

      # Base values (budgets, XP) are untouched.
      assert Characters.trait_values(character) |> Map.values() |> Enum.sort() == [2, 3]
    end

    test "tracker maximums use the effective values", %{story: story, character: character} do
      tracker_fixture(story, %{"name" => "Health", "max_formula" => "body + 2"})
      assert Trackers.get(character, "health").max == 6
    end

    test "dice pools use the effective values", %{character: character} do
      assert {:ok, result} =
               Dice.roll(character, %{"expression" => "1d6", "items" => ["body"]},
                 config: %Config{system: "expression"},
                 rng: fn _ -> 1 end
               )

      assert [%{"slug" => "body", "value" => 4}] = result["items"]
      assert result["total"] == 5
    end

    test "nothing applies when the module is disabled", %{story: story, character: character} do
      {:ok, story} = Stories.set_module_enabled(story, :origins, false)
      character = %{character | story: story}

      assert Origins.bonuses(character) == %{}
      assert %{"body" => 3, "empathy" => 2} = Characters.values_by_slug(character)
      assert Origins.character_origins(character) == []
      assert Origins.missing_required(character) == []
    end
  end
end
