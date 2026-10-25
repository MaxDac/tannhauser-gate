defmodule TannhauserGate.EsitiTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Esiti, Experience, Items, Mailbox, Repo, Stories, Trackers}
  alias TannhauserGate.Esiti.Esito
  alias TannhauserGate.Items.CharacterItem

  setup do
    {story, gm} = gdr_fixture()
    story = enable_modules(story, [:esiti])
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    alice = user_fixture()
    bob = user_fixture()

    %{
      story: story,
      gm: gm,
      master: master,
      alice: alice,
      a: character_fixture(alice, story),
      bob: bob,
      b: character_fixture(bob, story)
    }
  end

  defp file!(ctx, attrs \\ %{}) do
    {:ok, esito} =
      Esiti.create_esito(
        ctx.alice,
        ctx.story,
        Enum.into(attrs, %{
          "character_id" => to_string(ctx.a.id),
          "title" => "Night at the warehouse",
          "body" => "I sneak in **after midnight**."
        })
      )

    esito
  end

  defp balance(character), do: Characters.get_character!(character.id).balance

  describe "filing" do
    test "a player files a request for their character", ctx do
      location = location_fixture(ctx.story)

      esito =
        file!(ctx, %{
          "location_id" => to_string(location.id),
          "related_ids" => [to_string(ctx.b.id)]
        })

      assert esito.status == "open"
      assert esito.character_id == ctx.a.id
      assert esito.location_id == location.id
      assert [related] = esito.related_characters
      assert related.id == ctx.b.id
      assert [%{id: id}] = Esiti.list_user_esiti(ctx.alice, ctx.story)
      assert id == esito.id
      assert Esiti.list_user_esiti(ctx.bob, ctx.story) == []
      assert Esiti.open_count(ctx.story) == 1

      # The masters get a letter.
      assert [letter] = Mailbox.list_inbox(ctx.master, ctx.story)
      assert letter.subject =~ "New esito"
    end

    test "only own playable characters can file", ctx do
      assert {:error, :character_not_found} =
               Esiti.create_esito(ctx.bob, ctx.story, %{
                 "character_id" => to_string(ctx.a.id),
                 "title" => "T",
                 "body" => "B"
               })
    end

    test "validates title and body", ctx do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Esiti.create_esito(ctx.alice, ctx.story, %{"character_id" => to_string(ctx.a.id)})

      assert %{title: _, body: _} = errors_on(changeset)
    end

    test "rejects rooms, zones and related characters of another GDR", ctx do
      {other, _gm} = gdr_fixture()
      foreign_room = location_fixture(other)
      foreign = character_fixture(user_fixture(), other)
      base = %{"character_id" => to_string(ctx.a.id), "title" => "T", "body" => "B"}

      assert {:error, :location_not_found} =
               Esiti.create_esito(
                 ctx.alice,
                 ctx.story,
                 Map.put(base, "location_id", to_string(foreign_room.id))
               )

      assert {:error, :character_not_found} =
               Esiti.create_esito(
                 ctx.alice,
                 ctx.story,
                 Map.put(base, "related_ids", [to_string(foreign.id)])
               )

      assert {:error, :zone_not_found} =
               Esiti.create_esito(ctx.alice, ctx.story, Map.put(base, "zone_id", "999999"))
    end

    test "limits the open requests per character", ctx do
      {:ok, story} = Stories.update_story_as_gm(ctx.story, %{"esiti_max_open" => "1"})
      ctx = %{ctx | story: story}
      first = file!(ctx)
      assert {:error, :too_many_open} = Esiti.create_esito(ctx.alice, story, valid(ctx))

      # Claimed requests still count, closed ones do not.
      {:ok, _} = Esiti.claim(ctx.master, story, first)
      assert {:error, :too_many_open} = Esiti.create_esito(ctx.alice, story, valid(ctx))
      {:ok, _} = Esiti.withdraw(ctx.alice, story, Esiti.get_esito(story, first.id))
      assert {:ok, _} = Esiti.create_esito(ctx.alice, story, valid(ctx))

      {:ok, story} = Stories.update_story_as_gm(story, %{"esiti_max_open" => ""})
      assert story.esiti_max_open == nil
      assert {:ok, _} = Esiti.create_esito(ctx.alice, story, valid(ctx))
    end

    test "requires the minimum earned XP", ctx do
      {:ok, story} = Stories.update_story_as_gm(ctx.story, %{"esiti_min_xp" => "10"})
      assert {:error, :not_enough_xp} = Esiti.create_esito(ctx.alice, story, valid(ctx))
      {:ok, _} = Experience.award(ctx.master, ctx.a, 10, "Good roleplay")
      assert {:ok, _} = Esiti.create_esito(ctx.alice, story, valid(ctx))
    end

    test "refuses when the module is disabled", ctx do
      {:ok, story} = Stories.set_module_enabled(ctx.story, :esiti, false)
      assert {:error, :module_disabled} = Esiti.create_esito(ctx.alice, story, valid(ctx))
      assert Esiti.open_count(story) == 0
    end
  end

  defp valid(ctx),
    do: %{"character_id" => to_string(ctx.a.id), "title" => "Another", "body" => "Again"}

  describe "status transitions and thread" do
    test "claim, release, dismiss and withdraw", ctx do
      esito = file!(ctx)

      assert {:error, :unauthorized} = Esiti.claim(ctx.alice, ctx.story, esito)
      assert {:ok, claimed} = Esiti.claim(ctx.master, ctx.story, esito)
      assert claimed.status == "claimed"
      assert claimed.claimed_by_id == ctx.master.id
      assert {:error, :invalid_status} = Esiti.claim(ctx.gm, ctx.story, claimed)
      assert {:ok, released} = Esiti.release(ctx.master, ctx.story, claimed)
      assert released.status == "open" and is_nil(released.claimed_by_id)

      assert {:error, :unauthorized} = Esiti.withdraw(ctx.bob, ctx.story, released)
      assert {:ok, closed} = Esiti.withdraw(ctx.alice, ctx.story, released)
      assert closed.status == "closed"
      assert {:error, :invalid_status} = Esiti.dismiss(ctx.master, ctx.story, closed)

      other = file!(ctx, %{"title" => "Other"})
      assert {:ok, %{status: "closed"}} = Esiti.dismiss(ctx.master, ctx.story, other)
    end

    test "owner and masters post while active; others can't", ctx do
      esito = file!(ctx)

      assert {:ok, mine} = Esiti.post_message(ctx.alice, ctx.story, esito, %{"body" => "Hi"})
      assert mine.author_name == ctx.a.name and not mine.from_masters

      assert {:ok, theirs} = Esiti.post_message(ctx.master, ctx.story, esito, %{"body" => "Ok"})
      assert theirs.author_name == "The masters" and theirs.from_masters

      assert {:ok, signed} =
               Esiti.post_message(ctx.master, ctx.story, esito, %{"body" => "Me", "as" => "self"})

      assert signed.author_name =~ ctx.master.username

      assert {:error, :unauthorized} =
               Esiti.post_message(ctx.bob, ctx.story, esito, %{"body" => "Nope"})

      refute Esiti.can_view?(ctx.bob, ctx.story, esito)
      assert length(Esiti.list_messages(esito)) == 3

      {:ok, closed} = Esiti.withdraw(ctx.alice, ctx.story, esito)

      assert {:error, :not_active} =
               Esiti.post_message(ctx.alice, ctx.story, closed, %{"body" => "Late"})
    end

    test "esiti of another GDR are not reachable", ctx do
      esito = file!(ctx)
      {other, other_gm} = gdr_fixture()
      other = enable_modules(other, [:esiti])
      assert Esiti.get_esito(other, esito.id) == nil
      assert {:error, :esito_not_found} = Esiti.claim(other_gm, other, esito)
    end
  end

  describe "resolve/5" do
    test "applies the outcome, dice and effects to the requester", ctx do
      tracker = tracker_fixture(ctx.story, %{"name" => "Stress", "slug" => "stress"})
      esito = file!(ctx)

      assert {:ok, resolved} =
               Esiti.resolve(ctx.master, ctx.story, esito, %{
                 "outcome" => "You find the **crates**.",
                 "roll" => "true",
                 "dice" => %{"modifier" => "2"},
                 "xp" => "5",
                 "money" => "30",
                 "tracker" => tracker.slug,
                 "tracker_delta" => "-2"
               })

      assert resolved.status == "resolved"
      assert resolved.resolved_by_id == ctx.master.id
      assert is_map(resolved.dice_result) and resolved.dice_result["summary"]
      assert resolved.effects["xp"] == 5
      assert resolved.effects["money"] == 30
      assert resolved.effects["tracker"]["name"] == "Stress"
      assert Experience.totals(ctx.a).earned == 5
      assert balance(ctx.a) == 30
      assert Trackers.get(ctx.a, "stress").value == 3
      assert Enum.any?(Esiti.effect_lines(resolved.effects), &(&1 =~ "XP: +5"))

      [entry] = Experience.list_entries(ctx.a)
      assert entry.reason == "Esito: Night at the warehouse"

      # The requester gets a letter from the masters.
      assert [letter] = Mailbox.list_inbox(ctx.alice, ctx.story)
      assert letter.subject =~ "Esito resolved"

      assert {:error, :invalid_status} =
               Esiti.resolve(ctx.master, ctx.story, resolved, %{"outcome" => "Again"})
    end

    test "rewards the related characters too when asked", ctx do
      esito = file!(ctx, %{"related_ids" => [to_string(ctx.b.id)]})

      {:ok, _} =
        Esiti.resolve(ctx.master, ctx.story, esito, %{
          "outcome" => "Both get paid.",
          "money" => "10",
          "also_related" => "true"
        })

      assert balance(ctx.a) == 10
      assert balance(ctx.b) == 10
    end

    test "only masters resolve, and an outcome is required", ctx do
      esito = file!(ctx)

      assert {:error, :unauthorized} =
               Esiti.resolve(ctx.alice, ctx.story, esito, %{"outcome" => "x"})

      assert {:error, :outcome_required} = Esiti.resolve(ctx.master, ctx.story, esito, %{})
    end

    test "rolls everything back when an effect fails", ctx do
      esito = file!(ctx)

      # XP is applied first, then taking money the character doesn't have fails.
      assert {:error, :insufficient_funds} =
               Esiti.resolve(ctx.master, ctx.story, esito, %{
                 "outcome" => "Fined.",
                 "xp" => "5",
                 "money" => "-100"
               })

      assert Esiti.get_esito(ctx.story, esito.id).status == "open"
      assert Experience.totals(ctx.a).earned == 0
      assert balance(ctx.a) == 0
      assert Mailbox.list_inbox(ctx.alice, ctx.story) == []
    end

    test "grants items only with the items module, rolling back unknown items", ctx do
      story = enable_modules(ctx.story, [:items])
      {:ok, item} = Items.create_item(story, %{"name" => "Crowbar", "price" => 5})
      {other, _} = gdr_fixture()
      other = enable_modules(other, [:items])
      {:ok, foreign} = Items.create_item(other, %{"name" => "Foreign", "price" => 5})

      esito = file!(%{ctx | story: story})

      assert {:error, :item_not_found} =
               Esiti.resolve(ctx.master, story, esito, %{
                 "outcome" => "Loot.",
                 "money" => "10",
                 "item_id" => to_string(foreign.id),
                 "item_quantity" => "1"
               })

      assert balance(ctx.a) == 0
      assert Esiti.get_esito(story, esito.id).status == "open"

      assert {:ok, resolved} =
               Esiti.resolve(ctx.master, story, esito, %{
                 "outcome" => "Loot.",
                 "item_id" => to_string(item.id),
                 "item_quantity" => "2"
               })

      assert resolved.effects["item"] == %{"name" => "Crowbar", "quantity" => 2}
      assert Repo.get_by(CharacterItem, character_id: ctx.a.id, item_id: item.id).quantity == 2
    end

    test "ignores items when the items module is disabled", ctx do
      esito = file!(ctx)

      assert {:ok, resolved} =
               Esiti.resolve(ctx.master, ctx.story, esito, %{
                 "outcome" => "Nothing.",
                 "item_id" => "123",
                 "item_quantity" => "1"
               })

      assert resolved.effects["item"] == nil
    end

    test "counts per status", ctx do
      file!(ctx)
      esito = file!(ctx, %{"title" => "Second"})
      {:ok, _} = Esiti.claim(ctx.master, ctx.story, esito)
      assert %{"open" => 1, "claimed" => 1} = Esiti.status_counts(ctx.story)
      assert [%Esito{status: "claimed"}] = Esiti.list_queue(ctx.story, "mine", ctx.master)
      assert length(Esiti.list_queue(ctx.story, "active")) == 2
    end
  end
end
