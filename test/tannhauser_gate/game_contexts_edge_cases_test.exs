defmodule TannhauserGate.GameContextsEdgeCasesTest do
  @moduledoc """
  Edge cases (permissions, error branches, nil clauses and labels) of the
  formula, esiti, guilds, items, bank, diary and boards contexts.
  """
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bank, Boards, Characters, Diary, Esiti, Formula, Guilds, Items, Stories}
  alias TannhauserGate.Boards.Board
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Diary.Entry

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    player = user_fixture()

    %{
      story: story,
      gm: gm,
      master: master,
      player: player,
      character: character_fixture(player, story)
    }
  end

  describe "formula" do
    test "parse errors" do
      assert {:error, "unexpected number 2"} = Formula.parse("1 2")
      assert {:error, "unexpected " <> _} = Formula.parse("1 a")
      assert {:error, "is not a formula"} = Formula.parse(nil)
      assert {:error, "number " <> _} = Formula.parse("1234567890123")
      assert {:error, "contains invalid characters"} = Formula.parse(<<255>>)
      assert {:error, "is nested too deeply"} = Formula.parse(String.duplicate("(", 40) <> "1")
      assert {:error, "is nested too deeply"} = Formula.parse(String.duplicate("-", 40) <> "1")
      assert {:error, "unknown function foo"} = Formula.parse("foo(1)")
      assert {:error, _} = Formula.parse("max")
      assert {:error, _} = Formula.parse("max + 1")
      assert {:error, _} = Formula.parse("(1 +")
      assert {:error, _} = Formula.parse("max(1 2")
      assert {:error, _} = Formula.parse("max(1,")
    end

    test "identifiers and reserved names" do
      assert Formula.reserved() == ["min", "max"]
      assert Formula.identifiers("1 +") == []
      assert Formula.identifiers("-a + max(b, c)") == ["a", "b", "c"]
    end
  end

  describe "esiti" do
    setup ctx do
      story = enable_modules(ctx.story, [:esiti])

      {:ok, esito} =
        Esiti.create_esito(ctx.player, story, %{
          "character_id" => to_string(ctx.character.id),
          "title" => "Night at the warehouse",
          "body" => "I sneak in."
        })

      %{story: story, esito: esito}
    end

    defp resolve(ctx, attrs),
      do: Esiti.resolve(ctx.master, ctx.story, ctx.esito, Map.put(attrs, "outcome", "Done."))

    test "nil clauses and lookups", ctx do
      assert Esiti.enabled?(ctx.story.id)
      refute Esiti.enabled?(nil)
      assert Esiti.open_count(nil) == 0
      assert Esiti.get_esito(ctx.story, "abc") == nil
      refute Esiti.owner?(nil, ctx.esito)
      assert %Ecto.Changeset{} = Esiti.change_esito()
      assert %Ecto.Changeset{} = Esiti.change_message()
      assert Esiti.status_label("other") == "other"
      assert Esiti.effect_lines(nil) == []

      assert [%{id: id}] = Esiti.list_queue(ctx.story, "open")
      assert id == ctx.esito.id
      assert Esiti.list_queue(ctx.story, "resolved") == []
    end

    test "an empty message is a changeset error", ctx do
      assert {:error, %Ecto.Changeset{}} =
               Esiti.post_message(ctx.player, ctx.story, ctx.esito, %{"body" => ""})
    end

    test "invalid numbers in the resolution", ctx do
      assert {:error, :invalid_xp} = resolve(ctx, %{"xp" => "abc"})
      assert {:error, :invalid_xp} = resolve(ctx, %{"xp" => 1.5})
      assert {:error, :invalid_money} = resolve(ctx, %{"money" => "9999999"})
    end

    test "an integer XP reward and tracker damage types", ctx do
      tracker_fixture(ctx.story, %{
        "name" => "Wounds",
        "slug" => "wounds",
        "max_formula" => "5",
        "damage_types" => "light, deep"
      })

      assert {:ok, resolved} =
               resolve(ctx, %{
                 "xp" => 5,
                 "tracker" => "wounds",
                 "tracker_delta" => "1",
                 "tracker_damage_type" => "light"
               })

      assert resolved.effects["xp"] == 5
      assert resolved.effects["tracker"]["damage_type"] == "light"
      assert "Wounds: +1 (light)" in Esiti.effect_lines(resolved.effects)
    end

    test "dice errors roll everything back", ctx do
      assert {:error, {:dice, :unknown_item} = reason} =
               resolve(ctx, %{"roll" => "true", "dice" => %{"items" => ["nope"]}})

      assert Esiti.error_message(reason) =~ "Dice: "
      assert Esiti.get_esito(ctx.story, ctx.esito.id).status == "open"
    end

    test "error messages" do
      for reason <- [
            :module_disabled,
            :unauthorized,
            :muted,
            :esito_not_found,
            :character_not_found,
            :location_not_found,
            :zone_not_found,
            :too_many_related,
            :too_many_open,
            :not_enough_xp,
            :invalid_status,
            :not_active,
            :outcome_required,
            :outcome_too_long,
            :invalid_xp,
            :invalid_money,
            :invalid_quantity,
            :invalid_tracker_delta,
            :invalid_effect,
            :insufficient_funds,
            :insufficient_xp,
            :invalid_amount,
            :item_not_found,
            :not_found,
            :boom,
            "boom"
          ] do
        assert is_binary(Esiti.error_message(reason))
      end
    end
  end

  describe "guilds" do
    setup ctx do
      story = enable_modules(ctx.story, [:guilds])
      {:ok, guild} = Guilds.create_guild(story, %{name: "Police", open_join: true})
      {:ok, rank} = Guilds.create_rank(guild, %{name: "Cadet", salary: 0, position: 0})
      %{story: story, guild: Guilds.get_guild(story, guild.id), rank: rank}
    end

    test "updating the guild, its emblem and its ranks", ctx do
      assert {:ok, guild} = Guilds.update_guild(ctx.guild, %{name: "Militia"}, "/uploads/e.png")
      assert guild.name == "Militia"
      assert guild.emblem_path == "/uploads/e.png"
      assert {:ok, guild} = Guilds.remove_emblem(guild)
      assert guild.emblem_path == nil

      assert Guilds.get_rank(guild, "abc") == nil
      assert {:ok, rank} = Guilds.update_rank(ctx.rank, %{name: "Recruit"})
      assert rank.name == "Recruit"
      assert {:ok, _} = Guilds.delete_rank(rank)
      assert Guilds.get_rank(guild, rank.id) == nil
    end

    test "nil clauses", ctx do
      refute Guilds.enabled?(nil)
      refute Guilds.active_member_user?(nil, ctx.guild.id)
      refute Guilds.leader?(nil, ctx.guild)
      assert Guilds.user_memberships(nil, ctx.story) == []
      assert Guilds.public_guild_names(nil) == []
      assert Guilds.membership_for(nil, ctx.guild) == nil
      assert Guilds.get_membership(ctx.guild, "abc") == nil
    end

    test "a request is withdrawn by its owner", ctx do
      {:ok, membership} = Guilds.request_join(ctx.player, ctx.guild, ctx.character)

      assert {:error, :unauthorized} =
               Guilds.cancel_request(ctx.master, ctx.guild, membership)

      assert {:ok, _} = Guilds.cancel_request(ctx.player, ctx.guild, membership)
      assert Guilds.membership_for(ctx.character, ctx.guild) == nil
      assert "cancel" in Enum.map(Guilds.list_logs(ctx.guild), & &1.action)
    end

    test "accepting a stale invitation twice fails", ctx do
      {:ok, invitation} = Guilds.invite(ctx.master, ctx.story, ctx.guild, ctx.character.id)
      assert {:ok, _} = Guilds.accept_invitation(ctx.player, ctx.guild, invitation)

      assert {:error, :invalid_status} =
               Guilds.accept_invitation(ctx.player, ctx.guild, invitation)
    end

    test "enrolling with an unknown rank or character", ctx do
      assert {:error, :rank_not_found} =
               Guilds.enrol(ctx.master, ctx.story, ctx.guild, ctx.character.id, "999999")

      assert {:error, :character_not_found} =
               Guilds.enrol(ctx.master, ctx.story, ctx.guild, nil)

      assert Guilds.membership_for(ctx.character, ctx.guild) == nil
    end

    test "labels and error messages" do
      for action <- ~w(decline reject cancel leave expel other) do
        assert is_binary(Guilds.action_label(action))
      end

      assert Guilds.status_label("other") == "other"

      for reason <- [
            :module_disabled,
            :unauthorized,
            :character_not_found,
            :cannot_play,
            :invitation_only,
            :already_member,
            :too_many_guilds,
            :membership_not_found,
            :invalid_status,
            :rank_not_found,
            :guild_not_found,
            :boom
          ] do
        assert is_binary(Guilds.error_message(reason))
      end
    end
  end

  describe "items" do
    setup ctx do
      story = enable_modules(ctx.story, [:items])

      {:ok, item} =
        Items.create_item(story, %{"name" => "Blaster", "price" => 10, "slot" => "hand"})

      %{story: story, item: item, character: Characters.get_character!(ctx.character.id)}
    end

    test "catalog, shops and listings are updated and deleted", ctx do
      assert {:ok, item} = Items.update_item(ctx.story, ctx.item, %{"price" => 20}, "/i.png")
      assert item.price == 20
      assert item.image_path == "/i.png"
      assert {:ok, item} = Items.remove_item_image(item)
      assert item.image_path == nil

      {:ok, shop} = Items.create_shop(ctx.story, %{"name" => "Bazaar"})
      assert Items.get_shop(ctx.story, "abc") == nil
      assert {:ok, shop} = Items.update_shop(ctx.story, shop, %{"name" => "Market"})
      assert shop.name == "Market"

      {:ok, listing} = Items.create_listing(ctx.story, shop, %{"item_id" => item.id})
      assert Items.get_listing(ctx.story, listing.id).id == listing.id
      assert {:ok, listing} = Items.update_listing(ctx.story, listing, %{"price" => 5})
      assert listing.price == 5
      assert {:ok, _} = Items.delete_listing(listing)
      assert Items.get_listing(ctx.story, listing.id) == nil

      assert {:ok, _} = Items.delete_shop(shop)
      assert Items.get_shop(ctx.story, shop.id) == nil
    end

    test "unsaved characters, bad ids and idempotent equipping", ctx do
      refute Items.enabled?(nil)
      assert Items.inventory(%Character{}) == []
      assert Items.equipment_modifiers(%Character{}) == %{}
      assert {:error, :listing_not_found} = Items.buy(ctx.character, "abc", 1, ctx.player)
      assert {:error, :item_not_found} = Items.grant(ctx.character, nil, 1, ctx.player)

      {:ok, _} = Items.grant(ctx.character, ctx.item.id, 1, ctx.master)
      assert {:ok, _} = Items.unequip(ctx.character, ctx.item.id, ctx.player)
      assert {:ok, _} = Items.equip(ctx.character, ctx.item.id, ctx.player)
      assert {:ok, _} = Items.equip(ctx.character, ctx.item.id, ctx.player)

      actions =
        ctx.story
        |> Items.list_logs(character_id: to_string(ctx.character.id))
        |> Enum.map(& &1.action)

      assert Enum.sort(actions) == ["equip", "grant"]
      assert Items.list_logs(ctx.story, character_id: "999999") == []
    end

    test "using an item with a damage type", ctx do
      wounds =
        tracker_fixture(ctx.story, %{
          "name" => "Wounds",
          "slug" => "wounds",
          "max_formula" => "5",
          "damage_types" => "light, deep"
        })

      {:ok, kit} =
        Items.create_item(ctx.story, %{
          name: "Kit",
          price: 1,
          tracker_id: wounds.id,
          effect_change: 1,
          effect_damage_type: "light"
        })

      {:ok, _} = Items.grant(ctx.character, kit.id, 1, ctx.master)
      assert {:ok, %{item: used}} = Items.use_item(ctx.character, kit.id, ctx.player)
      assert used.id == kit.id
    end

    test "labels and error messages" do
      for action <- ~w(give buy use equip unequip other) do
        assert is_binary(Items.action_label(action))
      end

      for reason <- [
            :module_disabled,
            :alt_blocked,
            :item_not_found,
            :listing_not_found,
            :recipient_not_found,
            :same_character,
            :invalid_quantity,
            :not_enough_items,
            :not_owned,
            :not_stackable,
            :not_equippable,
            :not_usable,
            :out_of_stock,
            :insufficient_funds,
            :boom
          ] do
        assert is_binary(Items.error_message(reason))
      end
    end
  end

  describe "bank" do
    test "jobs are updated, removed and unassigned", ctx do
      job = job_fixture(ctx.story)
      assert Bank.get_job!(ctx.story, job.id).id == job.id
      assert {:ok, job} = Bank.update_job(job, %{pay: 25})
      assert job.pay == 25

      {:ok, character} = Bank.set_job(ctx.character, job.id)
      assert character.job_id == job.id
      assert {:ok, character} = Bank.set_job(character, nil)
      assert character.job_id == nil

      assert {:ok, _} = Bank.delete_job(job)
      assert Bank.list_jobs(ctx.story) == []
    end

    test "a never paid character is due", ctx do
      job = job_fixture(ctx.story, %{pay: 7})

      {:ok, _} =
        ctx.character
        |> Ecto.Changeset.change(job_id: job.id, last_paid_at: nil)
        |> Repo.update()

      assert Bank.pay_due() >= 1
      assert Characters.get_character!(ctx.character.id).balance == 7
    end

    test "invalid transfers and zero charges", ctx do
      other = character_fixture(user_fixture(), ctx.story)
      {:ok, _} = Bank.adjust(ctx.character, 100)

      assert {:error, :invalid_amount} = Bank.transfer(ctx.character, other.id, "abc")
      assert {:error, :invalid_amount} = Bank.transfer(ctx.character, other.id, 2_000_000_000)
      assert {:error, :invalid_amount} = Bank.transfer(ctx.character, other.id, nil)
      assert {:error, :recipient_not_found} = Bank.transfer(ctx.character, "abc", 5)
      assert {:ok, nil} = Bank.charge(Repo, ctx.character, 0, "Free")
    end

    test "error messages" do
      for reason <- [
            :insufficient_funds,
            :invalid_amount,
            :recipient_not_found,
            :same_character,
            :alt_blocked,
            :job_not_found,
            :boom
          ] do
        assert is_binary(Bank.error_message(reason))
      end
    end
  end

  describe "diary" do
    setup ctx do
      story = enable_modules(ctx.story, [:diary])
      %{story: story, character: Characters.get_character!(ctx.character.id)}
    end

    test "module checks resolve the story of a bare character", ctx do
      assert Diary.enabled?(ctx.story.id)
      refute Diary.enabled?(nil)

      bare = Repo.get!(Character, ctx.character.id)
      assert {:ok, entry} = Diary.create_entry(ctx.player, bare, %{"title" => "T", "body" => "B"})
      assert [%{id: id}] = Diary.list_entries(bare, ctx.player)
      assert id == entry.id
    end

    test "visibility, lookups and missing images", ctx do
      assert Diary.visible?(%Entry{visibility: "public"}, nil, ctx.character)
      refute Diary.visible?(%Entry{visibility: "private"}, nil, ctx.character)
      assert Diary.visible?(%Entry{visibility: "private"}, ctx.player, ctx.character)
      assert Diary.get_entry(ctx.character, "abc") == nil
      assert {:error, :not_found} = Diary.delete_image(ctx.player, ctx.character, "abc")
      assert Diary.visibility_label("public") == "Public"
    end

    test "error messages" do
      for reason <- [
            :module_disabled,
            :muted,
            :unauthorized,
            :not_found,
            :gallery_full,
            :too_large,
            :invalid_image,
            %Ecto.Changeset{},
            :boom
          ] do
        assert is_binary(Diary.error_message(reason))
      end
    end
  end

  describe "boards" do
    setup ctx, do: %{story: enable_modules(ctx.story, [:boards])}

    test "nil clauses and invalid ids", ctx do
      assert Boards.enabled?(ctx.story.id)
      refute Boards.enabled?(nil)
      assert Boards.get_announcement(ctx.story, "abc") == nil
      assert Boards.unread_count(nil, ctx.story) == 0
      assert Boards.last_seen_at(nil, ctx.story) == nil
      assert Boards.mark_announcements_read(nil, ctx.story) == :ok
      assert Boards.get_board(ctx.story, "abc") == nil
      assert Boards.get_notice(ctx.story, "abc") == nil
      assert Boards.place_label(%Board{}) == "—"
    end

    test "masters update and delete boards", ctx do
      room = location_fixture(ctx.story)

      {:ok, board} =
        Boards.create_board(ctx.master, ctx.story, %{"name" => "Wall", "location_id" => room.id})

      assert {:error, :unauthorized} =
               Boards.update_board(ctx.player, ctx.story, board, %{"name" => "Mine"})

      assert {:ok, board} = Boards.update_board(ctx.master, ctx.story, board, %{"name" => "Pole"})
      assert board.name == "Pole"

      assert {:error, :unauthorized} = Boards.delete_board(ctx.player, ctx.story, board)
      assert {:ok, _} = Boards.delete_board(ctx.master, ctx.story, board)
      assert Boards.get_board(ctx.story, board.id) == nil
    end

    test "error messages" do
      for reason <- [:module_disabled, :unauthorized, :muted, :not_found, :boom] do
        assert is_binary(Boards.error_message(reason))
      end
    end
  end
end
