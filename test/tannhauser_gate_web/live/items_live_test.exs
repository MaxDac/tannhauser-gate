defmodule TannhauserGateWeb.ItemsLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bank, Characters, Items, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  # Enables the module, then creates a character for the player, an item
  # catalog and a shop in a room.
  defp with_items(ctx) do
    story = enable_modules(ctx.story, [:items])
    sheet_item_fixture(story, %{name: "Firearms"})
    location = location_fixture(story)
    character = character_fixture(ctx.player, story)

    {:ok, pistol} =
      Items.create_item(story, %{
        name: "Blaster pistol",
        price: 100,
        slot: "weapon",
        stackable: false,
        modifiers: %{"firearms" => 2}
      })

    {:ok, medkit} = Items.create_item(story, %{name: "Medkit", price: 10})
    {:ok, shop} = Items.create_shop(story, %{name: "Black market", location_id: location.id})
    {:ok, listing} = Items.create_listing(story, shop, %{item_id: pistol.id, stock: 1})

    Map.merge(ctx, %{
      story: story,
      location: location,
      character: character,
      pistol: pistol,
      medkit: medkit,
      shop: shop,
      listing: listing
    })
  end

  describe "module disabled" do
    test "pages redirect and links are hidden", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm")
      refute has_element?(lv, "#gm-tab-items")
      refute has_element?(lv, "#gm-tab-shops")
      refute has_element?(lv, "#nav-market")

      for path <- [
            ~p"/g/#{ctx.story}/gm/items",
            ~p"/g/#{ctx.story}/gm/shops",
            ~p"/g/#{ctx.story}/market",
            ~p"/g/#{ctx.story}/master/items"
          ] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.gm), path)
        assert to == ~p"/g/#{ctx.story}"
      end
    end
  end

  describe "GM pages" do
    setup :with_items

    test "masters who are not GDR admins cannot reach them", ctx do
      for path <- [~p"/g/#{ctx.story}/gm/items", ~p"/g/#{ctx.story}/gm/shops"] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.master), path)
        assert to == ~p"/g/#{ctx.story}"
      end
    end

    test "the GDR admin manages the catalog", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm")
      assert has_element?(lv, "#gm-tab-items")
      assert has_element?(lv, "#nav-market")

      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/items")
      assert has_element?(lv, "#catalog-item-#{ctx.pistol.id}")
      assert has_element?(lv, "#catalog-item-modifiers-#{ctx.pistol.id}", "+2")

      lv
      |> form("#item-form", item: %{name: "Trench coat", price: "-1"})
      |> render_submit()

      assert Enum.count(Items.list_items(ctx.story)) == 2

      lv
      |> form("#item-form",
        item: %{name: "Trench coat", price: "120", slot: "body", modifiers: %{"firearms" => "1"}}
      )
      |> render_submit()

      coat = Enum.find(Items.list_items(ctx.story), &(&1.name == "Trench coat"))
      assert coat.slot == "body"
      assert coat.modifiers == %{"firearms" => 1}
      assert has_element?(lv, "#catalog-item-#{coat.id}")

      lv |> element("#delete-item-#{coat.id}") |> render_click()
      refute has_element?(lv, "#catalog-item-#{coat.id}")
    end

    test "the GDR admin manages shops and listings", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/shops")
      assert has_element?(lv, "#shop-#{ctx.shop.id}")
      assert has_element?(lv, "#listing-#{ctx.listing.id}")

      lv |> form("#shop-form", shop: %{name: "Pawn shop"}) |> render_submit()
      pawn = Enum.find(Items.list_shops(ctx.story), &(&1.name == "Pawn shop"))
      assert has_element?(lv, "#shop-#{pawn.id}")

      lv |> element("#new-listing-#{pawn.id}") |> render_click()

      lv
      |> form("#listing-form", listing: %{item_id: ctx.medkit.id, price: "5", stock: "3"})
      |> render_submit()

      assert [%{price: 5, stock: 3, item_id: item_id}] =
               Items.get_shop!(ctx.story, pawn.id).listings

      assert item_id == ctx.medkit.id
    end
  end

  describe "market" do
    setup :with_items

    test "a player buys an item", ctx do
      {:ok, _} = Bank.adjust(ctx.character, 150)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/market")
      assert has_element?(lv, "#market-shop-#{ctx.shop.id}")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/market/#{ctx.shop}")
      assert has_element?(lv, "#shop-room-link")

      lv
      |> form("#buy-form-#{ctx.listing.id}", %{"quantity" => "1"})
      |> render_submit()

      assert render(lv) =~ "Bought 1× Blaster pistol"
      assert Characters.get_character!(ctx.character.id).balance == 50
      assert [%{quantity: 1}] = Items.inventory(ctx.character)
    end

    test "insufficient funds are reported", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/market/#{ctx.shop}")

      lv
      |> form("#buy-form-#{ctx.listing.id}", %{"quantity" => "1"})
      |> render_submit()

      assert Items.inventory(ctx.character) == []
      assert has_element?(lv, "#shop-stock-#{ctx.listing.id}", "1")
    end

    test "a shop of another GDR is rejected", ctx do
      {other, _gm} = gdr_fixture()
      other = enable_modules(other, [:items])
      {:ok, foreign} = Items.create_shop(other, %{name: "Elsewhere"})

      assert {:error, {:live_redirect, %{to: to, flash: %{"error" => _}}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/market/#{foreign}")

      assert to == ~p"/g/#{ctx.story}/market"
    end

    test "rooms link their shops", ctx do
      {:ok, lv, _} =
        live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")

      assert has_element?(lv, "#room-shop-#{ctx.shop.id}")
    end
  end

  describe "master items page" do
    setup :with_items

    test "players cannot reach it", ctx do
      assert {:error, {_, %{to: _}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/items")
    end

    test "masters grant and remove items and read the log", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      assert has_element?(lv, "#master-items")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/items")

      lv
      |> form("#grant-form",
        grant: %{character_id: ctx.character.id, item_id: ctx.medkit.id, quantity: "3"}
      )
      |> render_submit(%{"op" => "grant"})

      assert [%{quantity: 3}] = Items.inventory(ctx.character)

      lv
      |> form("#grant-form",
        grant: %{character_id: ctx.character.id, item_id: ctx.medkit.id, quantity: "1"}
      )
      |> render_submit(%{"op" => "remove"})

      assert [%{quantity: 2}] = Items.inventory(ctx.character)
      assert [%{action: "remove"}, %{action: "grant"}] = Items.list_logs(ctx.story)
      assert has_element?(lv, "#item-logs li", "Medkit")
    end
  end

  describe "character sheet" do
    setup :with_items

    setup ctx do
      {:ok, _} = Items.grant(ctx.character, ctx.pistol.id, 1, ctx.gm, nil)
      {:ok, _} = Items.grant(ctx.character, ctx.medkit.id, 2, ctx.gm, nil)
      :ok
    end

    test "the owner equips and gives items", ctx do
      friend = character_fixture(user_fixture(), ctx.story)
      path = ~p"/g/#{ctx.story}/characters/#{ctx.character}"
      {:ok, lv, _} = live(conn_for(ctx.player), path)

      assert has_element?(lv, "#inventory-item-#{ctx.medkit.id}")
      lv |> element("#equip-item-#{ctx.pistol.id}") |> render_click()
      assert has_element?(lv, "#inventory-equipped-#{ctx.pistol.id}")

      assert Characters.values_by_slug(Characters.get_character!(ctx.character.id))["firearms"] ==
               2

      lv
      |> form("#give-item-form",
        give: %{item_id: ctx.medkit.id, quantity: "1", to: friend.id}
      )
      |> render_submit()

      assert [%{quantity: 1}] = Items.inventory(friend)

      lv |> element("#unequip-item-#{ctx.pistol.id}") |> render_click()
      refute has_element?(lv, "#inventory-equipped-#{ctx.pistol.id}")
    end

    test "the public sheet shows equipped items only", ctx do
      {:ok, _} = Items.equip(ctx.character, ctx.pistol.id, ctx.player)

      {:ok, lv, _} =
        live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      assert has_element?(lv, "#inventory-item-#{ctx.pistol.id}")
      refute has_element?(lv, "#inventory-item-#{ctx.medkit.id}")
      refute has_element?(lv, "#unequip-item-#{ctx.pistol.id}")

      render_click(lv, "unequip_item", %{"item" => to_string(ctx.pistol.id)})
      assert [%{equipped: true}] = Items.equipped(ctx.character)
    end

    test "masters remove items from the sheet", ctx do
      {:ok, lv, _} =
        live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      refute has_element?(lv, "#use-item-#{ctx.medkit.id}")
      lv |> element("#remove-item-#{ctx.medkit.id}") |> render_click()

      assert %{quantity: 1} =
               Enum.find(Items.inventory(ctx.character), &(&1.item_id == ctx.medkit.id))
    end
  end
end
