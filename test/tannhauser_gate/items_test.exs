defmodule TannhauserGate.ItemsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bank, Characters, Items, Repo, Trackers}
  alias TannhauserGate.Bank.Transaction
  alias TannhauserGate.Items.{CharacterItem, Listing, Log}

  setup do
    {story, gm} = gdr_fixture()
    story = enable_modules(story, [:items])
    firearms = sheet_item_fixture(story, %{name: "Firearms", kind: "skill"})
    character = character_fixture(user_fixture(), story)
    %{story: story, gm: gm, firearms: firearms, character: character}
  end

  defp item_fixture(story, attrs \\ %{}) do
    {:ok, item} =
      Items.create_item(
        story,
        Enum.into(attrs, %{"name" => "Item #{System.unique_integer([:positive])}", "price" => 10})
      )

    item
  end

  defp fund(character, amount) do
    {:ok, _} = Bank.adjust(character, amount)
    Characters.get_character!(character.id)
  end

  defp quantity(character, item) do
    case Repo.get_by(CharacterItem, character_id: character.id, item_id: item.id) do
      nil -> 0
      row -> row.quantity
    end
  end

  describe "catalog" do
    test "validates modifiers against the GDR's sheet items", %{story: story} do
      assert {:ok, item} =
               Items.create_item(story, %{
                 name: "Blaster",
                 price: 300,
                 slot: " weapon ",
                 modifiers: %{"firearms" => "2", "other" => ""}
               })

      assert item.modifiers == %{"firearms" => 2}
      assert item.slot == "weapon"

      assert {:error, changeset} =
               Items.create_item(story, %{name: "Bad", price: 1, modifiers: %{"nope" => 1}})

      assert "references unknown sheet item nope" in errors_on(changeset).modifiers

      assert {:error, changeset} = Items.create_item(story, %{name: "Neg", price: -1})
      assert errors_on(changeset).price != []
    end

    test "validates the consumable effect against the GDR's trackers", %{story: story} do
      health = tracker_fixture(story, %{"name" => "Health", "slug" => "health"})

      wounds =
        tracker_fixture(story, %{
          "name" => "Wounds",
          "slug" => "wounds",
          "damage_types" => "light, deep"
        })

      {other, _} = gdr_fixture()
      foreign = tracker_fixture(other)

      assert {:ok, _} =
               Items.create_item(story, %{
                 name: "Stim",
                 price: 1,
                 tracker_id: health.id,
                 effect_change: 2
               })

      assert {:error, changeset} =
               Items.create_item(story, %{
                 name: "Foreign",
                 price: 1,
                 tracker_id: foreign.id,
                 effect_change: 2
               })

      assert "is not a tracker of this GDR" in errors_on(changeset).tracker_id

      assert {:error, changeset} =
               Items.create_item(story, %{
                 name: "Kit",
                 price: 1,
                 tracker_id: wounds.id,
                 effect_change: -1
               })

      assert errors_on(changeset).effect_damage_type != []

      assert {:ok, kit} =
               Items.create_item(story, %{
                 name: "Kit",
                 price: 1,
                 tracker_id: wounds.id,
                 effect_change: -1,
                 effect_damage_type: "light"
               })

      assert kit.effect_damage_type == "light"
    end

    test "shops only reference rooms and items of the GDR", %{story: story} do
      {other, _} = gdr_fixture()
      foreign_room = location_fixture(other)
      foreign_item = item_fixture(enable_modules(other, [:items]))

      assert {:error, changeset} =
               Items.create_shop(story, %{name: "Shop", location_id: foreign_room.id})

      assert "is not a room of this GDR" in errors_on(changeset).location_id

      {:ok, shop} =
        Items.create_shop(story, %{name: "Shop", location_id: location_fixture(story).id})

      assert {:error, changeset} = Items.create_listing(story, shop, %{item_id: foreign_item.id})
      assert "is not an item of this GDR" in errors_on(changeset).item_id
    end
  end

  describe "grant, remove and give" do
    test "grant stacks and remove takes units away", %{story: story, gm: gm, character: c} do
      item = item_fixture(story)

      assert {:ok, _} = Items.grant(c, item.id, 2, gm, "Found it")
      assert {:ok, _} = Items.grant(c, to_string(item.id), "3", gm)
      assert quantity(c, item) == 5

      assert {:error, :not_enough_items} = Items.remove(c, item.id, 6, gm)
      assert {:ok, _} = Items.remove(c, item.id, 5, gm)
      assert quantity(c, item) == 0

      assert [
               %Log{action: "remove"},
               %Log{action: "grant"},
               %Log{action: "grant", note: "Found it"}
             ] =
               Items.list_logs(story)
    end

    test "non-stackable items are held once", %{story: story, gm: gm, character: c} do
      coat = item_fixture(story, %{"stackable" => false})

      assert {:error, :not_stackable} = Items.grant(c, coat.id, 2, gm)
      assert {:ok, _} = Items.grant(c, coat.id, 1, gm)
      assert {:error, :not_stackable} = Items.grant(c, coat.id, 1, gm)
    end

    test "cross-GDR ids are rejected", %{story: story, gm: gm, character: c} do
      {other, _} = gdr_fixture()
      other = enable_modules(other, [:items])
      foreign_item = item_fixture(other)
      foreign_character = character_fixture(user_fixture(), other)
      item = item_fixture(story)
      {:ok, _} = Items.grant(c, item.id, 1, gm)

      assert {:error, :item_not_found} = Items.grant(c, foreign_item.id, 1, gm)
      assert {:error, :recipient_not_found} = Items.give(c, foreign_character.id, item.id, 1, nil)
      assert {:error, :item_not_found} = Items.equip(c, foreign_item.id, nil)
    end

    test "give moves units to another approved character", %{story: story, gm: gm, character: c} do
      item = item_fixture(story)
      friend = character_fixture(user_fixture(), story)
      draft = draft_character_fixture(user_fixture(), story)
      {:ok, _} = Items.grant(c, item.id, 3, gm)

      assert {:error, :recipient_not_found} = Items.give(c, draft.id, item.id, 1, nil)
      assert {:error, :same_character} = Items.give(c, c.id, item.id, 1, nil)
      assert {:error, :not_enough_items} = Items.give(c, friend.id, item.id, 4, nil)
      assert {:error, :invalid_quantity} = Items.give(c, friend.id, item.id, 0, nil)

      assert {:ok, _} = Items.give(c, friend.id, item.id, 2, nil)
      assert quantity(c, item) == 1
      assert quantity(friend, item) == 2

      assert [%Log{action: "give", target_character_id: friend_id} | _] = Items.list_logs(story)
      assert friend_id == friend.id
    end

    test "everything is refused when the module is disabled", %{gm: gm} do
      {story, _} = gdr_fixture()
      character = character_fixture(user_fixture(), story)
      {:ok, item} = Items.create_item(story, %{name: "Thing", price: 1})

      assert {:error, :module_disabled} = Items.grant(character, item.id, 1, gm)
      assert Items.inventory(character) == []
      assert Items.equipment_modifiers(character) == %{}
    end
  end

  describe "equipment" do
    test "one item per slot, modifiers in the effective values", ctx do
      %{story: story, gm: gm, character: c} = ctx
      blaster = item_fixture(story, %{"slot" => "weapon", "modifiers" => %{"firearms" => 2}})
      rifle = item_fixture(story, %{"slot" => "weapon", "modifiers" => %{"firearms" => 3}})
      junk = item_fixture(story)
      {:ok, _} = Items.grant(c, blaster.id, 1, gm)
      {:ok, _} = Items.grant(c, rifle.id, 1, gm)
      {:ok, _} = Items.grant(c, junk.id, 1, gm)

      base = Characters.values_by_slug(c)["firearms"]

      assert {:error, :not_equippable} = Items.equip(c, junk.id, nil)
      assert {:ok, _} = Items.equip(c, blaster.id, nil)
      assert Characters.values_by_slug(c)["firearms"] == base + 2

      assert {:ok, %{unequipped: [unequipped]}} = Items.equip(c, rifle.id, nil)
      assert unequipped.id == blaster.id
      assert Characters.values_by_slug(c)["firearms"] == base + 3
      assert [%{item: %{id: rifle_id}}] = Items.equipped(c)
      assert rifle_id == rifle.id

      assert {:ok, _} = Items.unequip(c, rifle.id, nil)
      assert Characters.values_by_slug(c)["firearms"] == base

      # Not applied when the module is disabled.
      {:ok, _} = Items.equip(c, rifle.id, nil)
      {:ok, story} = TannhauserGate.Stories.set_module_enabled(story, :items, false)
      c = %{c | story: story}
      assert Characters.values_by_slug(c)["firearms"] == base
    end

    test "unowned items can't be equipped", %{story: story, character: c} do
      blaster = item_fixture(story, %{"slot" => "weapon"})
      assert {:error, :not_owned} = Items.equip(c, blaster.id, nil)
    end
  end

  describe "use" do
    test "applies the tracker effect and consumes a unit", %{story: story, gm: gm, character: c} do
      health =
        tracker_fixture(story, %{
          "name" => "Health",
          "slug" => "health",
          "max_formula" => "10"
        })

      {:ok, _} = Trackers.set(c, "health", 4)

      medkit =
        item_fixture(story, %{"tracker_id" => health.id, "effect_change" => 3})

      charm =
        item_fixture(story, %{
          "tracker_id" => health.id,
          "effect_change" => 1,
          "consumed_on_use" => false
        })

      plain = item_fixture(story)

      assert {:error, :not_enough_items} = Items.use_item(c, medkit.id, nil)
      {:ok, _} = Items.grant(c, medkit.id, 2, gm)
      {:ok, _} = Items.grant(c, charm.id, 1, gm)
      {:ok, _} = Items.grant(c, plain.id, 1, gm)

      assert {:ok, %{state: %{value: 7}}} = Items.use_item(c, medkit.id, nil)
      assert quantity(c, medkit) == 1

      assert {:ok, %{state: %{value: 8}}} = Items.use_item(c, charm.id, nil)
      assert quantity(c, charm) == 1

      assert {:error, :not_usable} = Items.use_item(c, plain.id, nil)
      assert [%Log{action: "use", note: "Health +1"} | _] = Items.list_logs(story)
    end
  end

  describe "buy" do
    setup %{story: story} do
      item = item_fixture(story, %{"name" => "Medkit", "price" => 50})
      {:ok, shop} = Items.create_shop(story, %{name: "Black market"})
      {:ok, listing} = Items.create_listing(story, shop, %{item_id: item.id, stock: 3})
      %{item: item, shop: shop, listing: listing}
    end

    test "charges the character, decrements the stock and logs", ctx do
      %{character: c, item: item, listing: listing} = ctx
      c = fund(c, 200)

      assert {:ok, %{total: 100}} = Items.buy(c, listing.id, 2, nil)
      assert Characters.get_character!(c.id).balance == 100
      assert quantity(c, item) == 2
      assert Repo.get!(Listing, listing.id).stock == 1

      assert %Transaction{kind: "purchase", amount: 100, note: "Bought 2× Medkit at Black market"} =
               Repo.get_by(Transaction, from_character_id: c.id)

      assert [%Log{action: "buy", quantity: 2}] = Items.list_logs(ctx.story)
    end

    test "fails atomically without funds or stock", ctx do
      %{character: c, item: item, listing: listing} = ctx
      c = fund(c, 60)

      assert {:error, :insufficient_funds} = Items.buy(c, listing.id, 2, nil)
      assert {:error, :out_of_stock} = Items.buy(c, listing.id, 4, nil)
      assert Characters.get_character!(c.id).balance == 60
      assert quantity(c, item) == 0
      assert Repo.get!(Listing, listing.id).stock == 3
      assert Items.list_logs(ctx.story) == []
    end

    test "the stock never goes negative under concurrent purchases", ctx do
      %{story: story, listing: listing} = ctx

      buyers =
        for _ <- 1..5 do
          story |> then(&character_fixture(user_fixture(), &1)) |> fund(100)
        end

      results =
        buyers
        |> Task.async_stream(&Items.buy(&1, listing.id, 1, nil), timeout: :infinity)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 3
      assert Enum.count(results, &(&1 == {:error, :out_of_stock})) == 2
      assert Repo.get!(Listing, listing.id).stock == 0
    end

    test "unlimited stock and price override", ctx do
      %{story: story, shop: shop, character: c} = ctx
      coat = item_fixture(story, %{"price" => 80})
      {:ok, listing} = Items.create_listing(story, shop, %{item_id: coat.id, price: 30})
      c = fund(c, 100)

      assert {:ok, %{total: 90}} = Items.buy(c, listing.id, 3, nil)
      assert is_nil(Repo.get!(Listing, listing.id).stock)
    end

    test "listings of another GDR are rejected", ctx do
      {other, _} = gdr_fixture()
      other_character = character_fixture(user_fixture(), enable_modules(other, [:items]))

      assert {:error, :listing_not_found} =
               Items.buy(other_character, ctx.listing.id, 1, nil)
    end
  end
end
