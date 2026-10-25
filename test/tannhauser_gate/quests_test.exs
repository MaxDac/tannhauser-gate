defmodule TannhauserGate.QuestsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Experience, Items, Quests, Repo, Stories}
  alias TannhauserGate.Items.CharacterItem

  setup do
    {story, gm} = gdr_fixture()
    story = enable_modules(story, [:quests])
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    alice = user_fixture()

    %{
      story: story,
      gm: gm,
      master: master,
      alice: alice,
      a: character_fixture(alice, story),
      b: character_fixture(user_fixture(), story)
    }
  end

  defp quest!(ctx, attrs \\ %{}) do
    {:ok, quest} =
      Quests.create_quest(
        ctx.master,
        ctx.story,
        Enum.into(attrs, %{"title" => "The blackout", "held_on" => "2026-10-01"})
      )

    quest
  end

  defp add!(ctx, quest, character, attrs) do
    {:ok, p} =
      Quests.add_participant(
        ctx.master,
        ctx.story,
        quest,
        Map.put(attrs, "character_id", to_string(character.id))
      )

    p
  end

  defp balance(character), do: Characters.get_character!(character.id).balance

  describe "quests" do
    test "masters record quests; players can't", ctx do
      quest = quest!(ctx, %{"summary" => "**Dark**", "visibility" => "masters"})
      assert quest.master_id == ctx.master.id
      assert quest.visibility == "masters"

      assert {:error, :unauthorized} =
               Quests.create_quest(ctx.alice, ctx.story, %{
                 "title" => "X",
                 "held_on" => "2026-10-01"
               })

      assert {:error, :unauthorized} = Quests.update_quest(ctx.alice, ctx.story, quest, %{})

      assert {:ok, updated} =
               Quests.update_quest(ctx.master, ctx.story, quest, %{"title" => "New"})

      assert updated.title == "New"
    end

    test "validates the chat-log range and the room", ctx do
      {other, _} = gdr_fixture()
      room = location_fixture(other)

      assert {:error, changeset} =
               Quests.create_quest(ctx.master, ctx.story, %{
                 "title" => "X",
                 "held_on" => "2026-10-01",
                 "location_id" => to_string(room.id),
                 "log_from" => "2026-10-02T10:00",
                 "log_to" => "2026-10-01T10:00"
               })

      assert %{location_id: _, log_to: _} = errors_on(changeset)
    end

    test "players see public quests, masters all of them", ctx do
      public = quest!(ctx, %{"title" => "Public"})
      secret = quest!(ctx, %{"title" => "Secret", "visibility" => "masters"})
      add!(ctx, public, ctx.a, %{})
      add!(ctx, secret, ctx.a, %{})

      assert [%{id: id}] = Quests.list_quests(ctx.story, ctx.alice)
      assert id == public.id
      assert length(Quests.list_quests(ctx.story, ctx.master)) == 2
      assert [%{id: ^id}] = Quests.character_quests(ctx.a, ctx.alice)
      assert length(Quests.character_quests(ctx.a, ctx.master)) == 2
      refute Quests.visible?(secret, ctx.story, ctx.alice)

      {:ok, story} = Stories.set_module_enabled(ctx.story, :quests, false)
      assert Quests.character_quests(%{ctx.a | story_id: story.id}, ctx.master) == []
    end

    test "quests of another GDR are not reachable", ctx do
      quest = quest!(ctx)
      {other, other_gm} = gdr_fixture()
      other = enable_modules(other, [:quests])
      assert Quests.get_quest(other, quest.id) == nil
      assert {:error, :quest_not_found} = Quests.apply_rewards(other_gm, other, quest)
      assert {:error, :quest_not_found} = Quests.delete_quest(other_gm, other, quest)

      foreign = character_fixture(user_fixture(), other)

      assert {:error, :character_not_found} =
               Quests.add_participant(ctx.master, ctx.story, quest, %{
                 "character_id" => to_string(foreign.id)
               })
    end
  end

  describe "apply_rewards/3" do
    test "hands out every reward once", ctx do
      story = enable_modules(ctx.story, [:items])
      ctx = %{ctx | story: story}
      {:ok, item} = Items.create_item(story, %{"name" => "Medal", "price" => 5})
      quest = quest!(ctx)

      add!(ctx, quest, ctx.a, %{
        "xp" => "5",
        "money" => "20",
        "item_id" => to_string(item.id),
        "item_quantity" => "2",
        "note" => "MVP"
      })

      add!(ctx, quest, ctx.b, %{"money" => "10"})

      assert {:error, %Ecto.Changeset{}} =
               Quests.add_participant(ctx.master, story, quest, %{
                 "character_id" => to_string(ctx.a.id)
               })

      assert {:error, :unauthorized} =
               Quests.apply_rewards(ctx.alice, story, Quests.get_quest(story, quest.id))

      assert {:ok, rewarded} =
               Quests.apply_rewards(ctx.master, story, Quests.get_quest(story, quest.id))

      assert rewarded.rewards_applied_at
      assert rewarded.rewards_applied_by_id == ctx.master.id
      assert Experience.totals(ctx.a).earned == 5
      assert [%{reason: "Quest: The blackout"}] = Experience.list_entries(ctx.a)
      assert balance(ctx.a) == 20
      assert balance(ctx.b) == 10
      assert Repo.get_by(CharacterItem, character_id: ctx.a.id, item_id: item.id).quantity == 2

      # Idempotent: a second run (even with a stale struct) does nothing.
      assert {:error, :already_rewarded} = Quests.apply_rewards(ctx.master, story, quest)
      assert balance(ctx.a) == 20

      # The participants are frozen.
      assert {:error, :already_rewarded} =
               Quests.add_participant(ctx.master, story, quest, %{
                 "character_id" => to_string(ctx.b.id)
               })

      [p | _] = rewarded.participants

      assert {:error, :already_rewarded} =
               Quests.remove_participant(ctx.master, story, quest, p.id)
    end

    test "rolls everything back when a reward fails", ctx do
      story = enable_modules(ctx.story, [:items])
      ctx = %{ctx | story: story}

      {:ok, item} =
        Items.create_item(story, %{"name" => "Badge", "price" => 5, "stackable" => false})

      quest = quest!(ctx)
      add!(ctx, quest, ctx.a, %{"xp" => "5", "money" => "20"})
      # Two units of a non-stackable item can't be granted.
      add!(ctx, quest, ctx.b, %{"item_id" => to_string(item.id), "item_quantity" => "2"})

      assert {:error, :not_stackable} =
               Quests.apply_rewards(ctx.master, story, Quests.get_quest(story, quest.id))

      assert Experience.totals(ctx.a).earned == 0
      assert balance(ctx.a) == 0
      refute Quests.get_quest(story, quest.id).rewards_applied_at
    end

    test "rejects items of another GDR and skips items without the module", ctx do
      quest = quest!(ctx)
      {other, _} = gdr_fixture()
      other = enable_modules(other, [:items])
      {:ok, foreign} = Items.create_item(other, %{"name" => "Foreign", "price" => 5})

      # Without the items module the item is ignored.
      p = add!(ctx, quest, ctx.a, %{"item_id" => to_string(foreign.id), "item_quantity" => "1"})
      assert p.item_id == nil

      story = enable_modules(ctx.story, [:items])

      assert {:error, :item_not_found} =
               Quests.add_participant(ctx.master, story, quest, %{
                 "character_id" => to_string(ctx.b.id),
                 "item_id" => to_string(foreign.id)
               })
    end

    test "validates the reward amounts", ctx do
      quest = quest!(ctx)

      assert {:error, changeset} =
               Quests.add_participant(ctx.master, ctx.story, quest, %{
                 "character_id" => to_string(ctx.a.id),
                 "xp" => "-1",
                 "money" => "-5"
               })

      assert %{xp: _, money: _} = errors_on(changeset)
    end
  end
end
