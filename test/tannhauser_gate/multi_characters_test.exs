defmodule TannhauserGate.MultiCharactersTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bank, Characters, Chat, Guilds, Items, Mailbox, Repo, Sanctions, Stories}
  alias TannhauserGate.Characters.Character

  defp allow(story, max, extra \\ %{}) do
    {:ok, story} =
      Stories.update_story_as_gm(story, Map.merge(%{"max_characters_per_user" => max}, extra))

    story
  end

  defp create(user, story, name) do
    Characters.create_character(user, %{"name" => name, "story_id" => story.id})
  end

  defp touch(character, seconds_ago) do
    at = DateTime.utc_now(:second) |> DateTime.add(-seconds_ago)
    character |> Ecto.Changeset.change(updated_at: at) |> Repo.update!()
  end

  setup do
    {story, gm} = gdr_fixture()
    %{story: story, gm: gm, player: user_fixture()}
  end

  describe "character limit" do
    test "the default limit of 1 keeps one character per user", ctx do
      assert ctx.story.max_characters_per_user == 1
      character_fixture(ctx.player, ctx.story)

      assert {:error, changeset} = create(ctx.player, ctx.story, "Second")
      assert "you already have a character in this GDR" in errors_on(changeset).story_id
      refute Characters.can_create_character?(ctx.player, ctx.story)
    end

    test "a higher limit allows more characters, up to the limit", ctx do
      story = allow(ctx.story, 2)
      assert {:ok, _} = create(ctx.player, story, "First")
      assert Characters.can_create_character?(ctx.player, story)
      assert {:ok, _} = create(ctx.player, story, "Second")
      refute Characters.can_create_character?(ctx.player, story)

      assert {:error, changeset} = create(ctx.player, story, "Third")

      assert "you already have the maximum number of characters in this GDR (2)" in errors_on(
               changeset
             ).story_id

      assert Characters.count_user_characters(ctx.player, story.id) == 2
    end

    test "drafts count, NPCs never do", ctx do
      {:ok, _npc} = Characters.create_npc(ctx.gm, ctx.story, %{"name" => "Informant"})
      {:ok, _npc} = Characters.create_npc(ctx.gm, ctx.story, %{"name" => "Bartender"})
      assert {:ok, draft} = create(ctx.gm, ctx.story, "GM's own")
      assert draft.approval_status == "draft"
      assert {:error, _} = create(ctx.gm, ctx.story, "Another")
    end

    test "limits are per GDR", ctx do
      other = story_fixture()
      character_fixture(ctx.player, ctx.story)
      assert {:ok, _} = create(ctx.player, other, "Elsewhere")
    end

    test "sequential creations past the limit are rejected (advisory lock + count)", ctx do
      story = allow(ctx.story, 3)

      results = for i <- 1..5, do: create(ctx.player, story, "Twin #{i}")

      assert Enum.count(results, &match?({:ok, _}, &1)) == 3
      assert Characters.count_user_characters(ctx.player, story.id) == 3
    end

    test "the GM setting is validated (1..10)", ctx do
      assert {:error, cs} =
               Stories.update_story_as_gm(ctx.story, %{"max_characters_per_user" => 0})

      assert errors_on(cs).max_characters_per_user != []

      assert {:error, cs} =
               Stories.update_story_as_gm(ctx.story, %{"max_characters_per_user" => 11})

      assert errors_on(cs).max_characters_per_user != []

      assert {:ok, %{max_characters_per_user: 10}} =
               Stories.update_story_as_gm(ctx.story, %{"max_characters_per_user" => 10})
    end
  end

  describe "active character" do
    setup ctx do
      story = allow(ctx.story, 3)
      old = character_fixture(ctx.player, story, %{name: "Deckard"}) |> touch(600)
      new = character_fixture(ctx.player, story, %{name: "Rachael"}) |> touch(60)
      %{story: story, old: old, new: new}
    end

    test "defaults to the most recently updated playable character", ctx do
      assert Characters.active_character(ctx.player, ctx.story).id == ctx.new.id

      {:ok, draft} = create(ctx.player, ctx.story, "Draft")
      assert draft.approval_status == "draft"
      assert Characters.active_character(ctx.player, ctx.story).id == ctx.new.id
    end

    test "falls back to any character when none can play", ctx do
      user = user_fixture()
      {:ok, draft} = create(user, ctx.story, "Draft")
      assert Characters.active_character(user, ctx.story).id == draft.id
      assert Characters.active_character(user_fixture(), ctx.story) == nil
    end

    test "switches to an owned character and orders selectors", ctx do
      assert {:ok, _} = Characters.set_active_character(ctx.player, ctx.old)
      assert Characters.active_character(ctx.player, ctx.story.id).id == ctx.old.id

      assert {[_, _], %Character{id: id}} =
               Characters.user_characters_with_active(ctx.player, ctx.story.id)

      assert id == ctx.old.id

      assert [%{id: first} | _] = Characters.playable_characters(ctx.player, ctx.story)
      assert first == ctx.old.id

      assert {:ok, _} = Characters.set_active_character(ctx.player, ctx.new)
      assert [%{id: first} | _] = Characters.playable_characters(ctx.player, ctx.story)
      assert first == ctx.new.id
    end

    test "only the owner can pick a character, never an NPC", ctx do
      assert {:error, :unauthorized} = Characters.set_active_character(user_fixture(), ctx.old)

      {:ok, npc} = Characters.create_npc(ctx.gm, ctx.story, %{"name" => "Informant"})
      assert {:error, :unauthorized} = Characters.set_active_character(ctx.gm, npc)
    end

    test "a deleted active character falls back to the default", ctx do
      {:ok, _} = Characters.set_active_character(ctx.player, ctx.old)
      {:ok, _} = Characters.delete_character(ctx.old)
      assert Characters.active_character(ctx.player, ctx.story).id == ctx.new.id
    end

    test "sanction letters go to the active character", ctx do
      {:ok, _} = Characters.set_active_character(ctx.player, ctx.old)
      story = enable_modules(ctx.story, [:reports])

      {:ok, _} =
        Sanctions.issue(ctx.gm, story, %{
          "user_id" => ctx.player.id,
          "kind" => "warning",
          "reason" => "Metagaming"
        })

      [letter] = Mailbox.list_inbox(ctx.player, story)
      assert letter.recipient_character_id == ctx.old.id
    end
  end

  describe "flows with two characters" do
    setup ctx do
      story = allow(ctx.story, 2)
      first = character_fixture(ctx.player, story, %{name: "Deckard"})
      second = character_fixture(ctx.player, story, %{name: "Rachael"})
      stranger = character_fixture(user_fixture(), story, %{name: "Gaff"})
      %{story: story, first: first, second: second, stranger: stranger}
    end

    test "bank transfers from either character", ctx do
      {:ok, _} = Bank.adjust(ctx.second, 50)
      assert {:ok, _} = Bank.transfer(ctx.second, ctx.stranger.id, 20)
      assert Characters.get_character!(ctx.stranger.id).balance == 20
    end

    test "market purchases with the second character", ctx do
      story = enable_modules(ctx.story, [:items])
      {:ok, item} = Items.create_item(story, %{name: "Medkit", price: 10})
      {:ok, shop} = Items.create_shop(story, %{name: "Pharmacy"})
      {:ok, listing} = Items.create_listing(story, shop, %{item_id: item.id})
      {:ok, _} = Bank.adjust(ctx.second, 15)
      second = Characters.get_character!(ctx.second.id)

      assert {:ok, %{quantity: 1}} = Items.buy(second, listing.id, 1, ctx.player)
      assert [%{quantity: 1}] = Items.inventory(second)
      assert Items.inventory(ctx.first) == []
    end

    test "both characters can join guilds", ctx do
      story = enable_modules(ctx.story, [:guilds])
      {:ok, guild} = Guilds.create_guild(story, %{name: "Police", open_join: true})
      {:ok, _} = Guilds.create_rank(guild, %{name: "Cadet", position: 0})

      assert {:ok, _} = Guilds.request_join(ctx.player, guild, ctx.first)
      assert {:ok, _} = Guilds.request_join(ctx.player, guild, ctx.second)
      assert length(Guilds.list_pending(guild)) == 2
    end

    test "mail can be sent as either character", ctx do
      for c <- [ctx.first, ctx.second] do
        assert {:ok, message} =
                 Mailbox.send_message(ctx.player, ctx.story, %{
                   "sender" => to_string(c.id),
                   "recipient" => to_string(ctx.stranger.id),
                   "subject" => "Hi",
                   "body" => "From #{c.name}"
                 })

        assert message.sender_character_id == c.id
      end
    end
  end

  describe "alt rules" do
    setup ctx do
      story = allow(ctx.story, 2)
      first = character_fixture(ctx.player, story, %{name: "Deckard"})
      second = character_fixture(ctx.player, story, %{name: "Rachael"})
      {:ok, _} = Bank.adjust(first, 100)
      %{story: story, first: first, second: second}
    end

    defp unblock(story, rule), do: allow(story, 2, %{to_string(rule) => false})

    test "alts?/2 ignores NPCs and the same character", ctx do
      assert Characters.alts?(ctx.first, ctx.second)
      refute Characters.alts?(ctx.first, ctx.first)
      {:ok, npc} = Characters.create_npc(ctx.gm, ctx.story, %{"name" => "Informant"})
      own = character_fixture(ctx.gm, ctx.story)
      refute Characters.alts?(npc, own)
    end

    test "bank transfers between alts are blocked by default", ctx do
      assert ctx.story.block_alt_transfers
      assert {:error, :alt_blocked} = Bank.transfer(ctx.first, ctx.second.id, 10)
      refute ctx.second.id in Enum.map(Bank.list_recipients(ctx.first), & &1.id)

      unblock(ctx.story, :block_alt_transfers)
      assert ctx.second.id in Enum.map(Bank.list_recipients(ctx.first), & &1.id)
      assert {:ok, _} = Bank.transfer(ctx.first, ctx.second.id, 10)
    end

    test "item gifts between alts are blocked by default", ctx do
      story = enable_modules(ctx.story, [:items])
      {:ok, item} = Items.create_item(story, %{name: "Medkit", price: 10})
      first = Characters.get_character!(ctx.first.id)
      {:ok, _} = Items.grant(first, item.id, 2, ctx.gm)

      assert {:error, :alt_blocked} = Items.give(first, ctx.second.id, item.id, 1, ctx.player)
      refute ctx.second.id in Enum.map(Items.give_recipients(first), & &1.id)

      unblock(story, :block_alt_transfers)
      assert {:ok, _} = Items.give(first, ctx.second.id, item.id, 1, ctx.player)
    end

    test "letters between alts are blocked by default", ctx do
      attrs = %{
        "sender" => to_string(ctx.first.id),
        "recipient" => to_string(ctx.second.id),
        "subject" => "Hi",
        "body" => "Me to me"
      }

      assert {:error, changeset} = Mailbox.send_message(ctx.player, ctx.story, attrs)
      assert hd(errors_on(changeset).recipient) =~ "another of your characters"

      story = unblock(ctx.story, :block_alt_mail)
      assert {:ok, _} = Mailbox.send_message(ctx.player, story, attrs)
    end

    test "whispers between alts are blocked by default", ctx do
      story = enable_modules(ctx.story, [:chat_rp])
      location = location_fixture(story)

      whisper = fn ->
        Chat.create_message(ctx.player, location, %{
          "character_id" => ctx.first.id,
          "kind" => "whisper",
          "body" => "psst",
          "recipient_character_id" => ctx.second.id
        })
      end

      assert {:error, :alt_blocked} = whisper.()
      unblock(story, :block_alt_whispers)
      assert {:ok, _} = whisper.()
    end
  end
end
