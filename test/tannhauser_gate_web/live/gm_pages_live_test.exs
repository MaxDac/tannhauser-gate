defmodule TannhauserGateWeb.GmPagesLiveTest do
  @moduledoc """
  Edit, validation and error flows of the GM dashboard sub-pages (items,
  shops, origins, weather table, zones and periodic actions).
  """
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Items, Origins, PeriodicActions, Stories, Weather, Zones}

  setup do
    {story, gm} = gdr_fixture()
    %{story: story, gm: gm}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp png_entry(name \\ "pic.png"), do: %{name: name, content: png_fixture(), type: "image/png"}

  describe "items" do
    setup ctx do
      story = enable_modules(ctx.story, [:items])
      sheet_item_fixture(story, %{name: "Body"})

      health =
        tracker_fixture(story, %{
          "name" => "Health",
          "max_formula" => "7",
          "damage_types" => "superficial,aggravated"
        })

      %{story: story, health: health}
    end

    test "validates, uploads an image, edits and removes it", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/items")

      lv |> form("#item-form", item: %{name: "", price: "-1"}) |> render_change()
      assert has_element?(lv, "#item-form", "can't be blank")

      image = file_input(lv, "#item-form", :image, [png_entry()])
      render_upload(image, "pic.png")
      assert has_element?(lv, "#item-form button[phx-click='cancel_upload']")

      lv
      |> form("#item-form", item: %{name: "Medkit", price: "10"})
      |> render_submit()

      assert [%{name: "Medkit", image_path: path} = item] = Items.list_items(ctx.story)
      assert is_binary(path)
      assert has_element?(lv, "#catalog-item-#{item.id} img")

      lv |> element("#edit-item-#{item.id}") |> render_click()
      assert has_element?(lv, "#item-image")
      assert has_element?(lv, "#cancel-item")

      lv |> element("#remove-item-image") |> render_click()
      refute has_element?(lv, "#item-image")
      assert %{image_path: nil} = Items.get_item!(ctx.story, item.id)

      lv |> form("#item-form", item: %{name: "Big medkit"}) |> render_submit()
      assert [%{name: "Big medkit"}] = Items.list_items(ctx.story)

      lv |> element("#edit-item-#{item.id}") |> render_click()
      lv |> element("#cancel-item") |> render_click()
      refute has_element?(lv, "#cancel-item")
    end

    test "a pending upload can be cancelled and bad files are rejected", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/items")

      image = file_input(lv, "#item-form", :image, [png_entry()])
      render_upload(image, "pic.png")
      lv |> element("#item-form button[phx-click='cancel_upload']") |> render_click()
      refute has_element?(lv, "#item-form button[phx-click='cancel_upload']")

      bad = file_input(lv, "#item-form", :image, [%{name: "notes.txt", content: "hi"}])
      assert {:error, [[_ref, :not_accepted]]} = render_upload(bad, "notes.txt")

      many = file_input(lv, "#item-form", :image, [png_entry("a.png"), png_entry("b.png")])
      assert {:error, errors} = render_upload(many, "a.png")
      assert Enum.any?(errors, &match?([_, :too_many_files], &1))
    end

    test "remove image without a saved item is a no-op", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/items")
      render_click(lv, "remove_image", %{})
      assert has_element?(lv, "#item-form")
    end

    test "consumable effects with damage types are shown in the form and catalog", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/items")

      lv
      |> form("#item-form", item: %{name: "Stim", price: "5", tracker_id: ctx.health.id})
      |> render_change()

      assert has_element?(lv, "#item_effect_change")
      assert has_element?(lv, "#item_effect_damage_type")
      assert has_element?(lv, "#item_consumed_on_use")

      lv
      |> form("#item-form",
        item: %{
          name: "Stim",
          price: "5",
          tracker_id: ctx.health.id,
          effect_change: "-2",
          effect_damage_type: "superficial"
        }
      )
      |> render_submit()

      assert [item] = Items.list_items(ctx.story)
      assert has_element?(lv, "#catalog-item-#{item.id}", "Health (superficial)")
    end
  end

  describe "shops" do
    setup ctx do
      story = enable_modules(ctx.story, [:items])
      {:ok, item} = Items.create_item(story, %{name: "Medkit", price: 10})
      {:ok, shop} = Items.create_shop(story, %{name: "Market"})
      {:ok, listing} = Items.create_listing(story, shop, %{item_id: item.id, stock: 2})
      %{story: story, item: item, shop: shop, listing: listing}
    end

    test "shops are validated, edited, cancelled and deleted", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/shops")

      lv |> form("#shop-form", shop: %{name: ""}) |> render_change()
      assert has_element?(lv, "#shop-form", "can't be blank")

      lv |> form("#shop-form", shop: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#shop-form", "can't be blank")

      lv |> element("#edit-shop-#{ctx.shop.id}") |> render_click()
      lv |> form("#shop-form", shop: %{name: "Bazaar"}) |> render_submit()
      assert [%{name: "Bazaar"}] = Items.list_shops(ctx.story)

      lv |> element("#edit-shop-#{ctx.shop.id}") |> render_click()
      lv |> element("#cancel-shop") |> render_click()
      refute has_element?(lv, "#cancel-shop")

      lv |> element("#delete-shop-#{ctx.shop.id}") |> render_click()
      assert Items.list_shops(ctx.story) == []
      assert has_element?(lv, "#shops-empty")
    end

    test "listings are validated, edited, cancelled and deleted", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/shops")

      lv |> element("#edit-listing-#{ctx.listing.id}") |> render_click()
      lv |> form("#listing-form", listing: %{stock: "-5"}) |> render_change()
      assert has_element?(lv, "#listing-form", "must be")

      lv |> form("#listing-form", listing: %{stock: "-5"}) |> render_submit()
      assert has_element?(lv, "#listing-form", "must be")

      lv |> form("#listing-form", listing: %{stock: "7"}) |> render_submit()
      assert has_element?(lv, "#listing-stock-#{ctx.listing.id}", "7")

      lv |> element("#new-listing-#{ctx.shop.id}") |> render_click()
      lv |> element("#cancel-listing") |> render_click()
      refute has_element?(lv, "#listing-form")

      lv |> element("#delete-listing-#{ctx.listing.id}") |> render_click()
      refute has_element?(lv, "#listing-#{ctx.listing.id}")
      assert Items.get_listing(ctx.story, ctx.listing.id) == nil
    end

    test "unknown listings are ignored", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/shops")
      render_click(lv, "edit_listing", %{"id" => "0"})
      refute has_element?(lv, "#listing-form")
      render_click(lv, "delete_listing", %{"id" => "0"})
      assert has_element?(lv, "#listing-#{ctx.listing.id}")
    end
  end

  describe "origins" do
    setup ctx do
      story = enable_modules(ctx.story, [:origins])
      sheet_item_fixture(story, %{name: "Body"})

      {:ok, group} =
        Origins.create_group(story, %{name: "Origin", description: "Where you come from"})

      {:ok, option} = Origins.create_option(story, %{group_id: group.id, name: "Human"})
      %{story: story, group: group, option: option}
    end

    test "groups are validated, edited and cancelled", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/origins")
      assert has_element?(lv, "#origin-group-#{ctx.group.id}", "Where you come from")

      lv |> form("#origin-group-form", group: %{name: ""}) |> render_change()
      assert has_element?(lv, "#origin-group-form", "can't be blank")

      lv |> form("#origin-group-form", group: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#origin-group-form", "can't be blank")

      lv |> element("#edit-origin-group-#{ctx.group.id}") |> render_click()
      lv |> form("#origin-group-form", group: %{name: "Ancestry"}) |> render_submit()
      assert [%{name: "Ancestry"}] = Origins.list_groups(ctx.story)

      lv |> element("#edit-origin-group-#{ctx.group.id}") |> render_click()
      lv |> element("#cancel-origin-group") |> render_click()
      refute has_element?(lv, "#cancel-origin-group")
    end

    test "options are validated, uploaded, edited and cancelled", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/origins")

      lv |> element("#new-option-#{ctx.group.id}") |> render_click()

      lv
      |> form("#origin-option-form", option: %{name: "", bonuses: %{"body" => "x"}})
      |> render_change()

      assert has_element?(lv, "#origin-option-form", "can't be blank")

      lv |> form("#origin-option-form", option: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#origin-option-form", "can't be blank")

      image = file_input(lv, "#origin-option-form", :image, [png_entry()])
      render_upload(image, "pic.png")

      lv
      |> form("#origin-option-form", option: %{name: "Android", bonuses: %{"body" => "1"}})
      |> render_submit()

      android = ctx.story |> Origins.list_groups() |> hd() |> Map.fetch!(:options)
      android = Enum.find(android, &(&1.name == "Android"))
      assert android.image_path
      assert has_element?(lv, "#origin-option-#{android.id} img")

      lv |> element("#edit-origin-option-#{android.id}") |> render_click()
      assert has_element?(lv, "#origin-option-image")
      lv |> element("#remove-origin-option-image") |> render_click()
      refute has_element?(lv, "#origin-option-image")

      lv |> form("#origin-option-form", option: %{name: "Synth"}) |> render_submit()
      assert has_element?(lv, "#origin-option-#{android.id}", "Synth")

      lv |> element("#edit-origin-option-#{ctx.option.id}") |> render_click()
      lv |> element("#cancel-origin-option") |> render_click()
      refute has_element?(lv, "#cancel-origin-option")
    end

    test "uploads can be cancelled and bad files are rejected", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/origins")

      image = file_input(lv, "#origin-option-form", :image, [png_entry()])
      render_upload(image, "pic.png")
      lv |> element("#origin-option-form button[phx-click='cancel_upload']") |> render_click()
      refute has_element?(lv, "#origin-option-form button[phx-click='cancel_upload']")

      bad = file_input(lv, "#origin-option-form", :image, [%{name: "notes.txt", content: "hi"}])
      assert {:error, [[_ref, :not_accepted]]} = render_upload(bad, "notes.txt")

      render_click(lv, "remove_image", %{})
      assert has_element?(lv, "#origin-option-form")
    end
  end

  describe "weather table" do
    setup ctx do
      story = enable_modules(ctx.story, [:weather])

      {:ok, rain} =
        Weather.create_condition(story, %{
          name: "Rain",
          icon: "hero-cloud-arrow-down",
          description: "Acid drizzle",
          weights: %{"default" => 3},
          temp_min: %{"default" => 2},
          temp_max: %{"default" => 9}
        })

      %{story: story, rain: rain}
    end

    test "conditions are validated, edited, cancelled and deleted", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/weather")
      assert has_element?(lv, "#weather-condition-#{ctx.rain.id}", "Acid drizzle")
      assert has_element?(lv, "#weather-condition-#{ctx.rain.id}", "2…9°C")

      lv
      |> form("#weather-condition-form",
        condition: %{name: "", weights: %{"default" => "abc"}, temp_min: %{"default" => "500"}}
      )
      |> render_change()

      assert has_element?(lv, "#weather-condition-form", "can't be blank")
      assert has_element?(lv, "#weather-condition-form", "weights must be whole numbers")
      assert has_element?(lv, "#weather-condition-form", "temperatures must be between")

      lv |> form("#weather-condition-form", condition: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#weather-condition-form", "can't be blank")

      lv |> element("#edit-weather-condition-#{ctx.rain.id}") |> render_click()
      lv |> form("#weather-condition-form", condition: %{name: "Storm"}) |> render_submit()
      assert [%{name: "Storm"}] = Weather.list_conditions(ctx.story)

      lv |> element("#edit-weather-condition-#{ctx.rain.id}") |> render_click()
      lv |> element("#cancel-weather-condition") |> render_click()
      refute has_element?(lv, "#cancel-weather-condition")

      render_click(lv, "edit", %{"id" => "0"})
      refute has_element?(lv, "#cancel-weather-condition")
      render_click(lv, "delete", %{"id" => "0"})
      assert has_element?(lv, "#weather-condition-#{ctx.rain.id}")
    end

    test "an invalid interval is rejected", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/weather")

      lv
      |> form("#weather-interval-form", settings: %{weather_interval_hours: "500"})
      |> render_submit()

      assert has_element?(lv, "#weather-interval-form", "must be less than or equal to 168")
      assert Stories.get_story!(ctx.story.id).weather_interval_hours == 6
    end
  end

  describe "zones" do
    setup ctx do
      {:ok, property} = Zones.create_property(ctx.story, %{name: "Danger", default_value: 1})
      {:ok, zone} = Zones.create_zone(ctx.story, %{name: "Docks", values: %{"danger" => 4}})
      %{property: property, zone: zone}
    end

    test "properties are edited, cancelled, rejected and deleted", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/zones")

      lv |> form("#property-form", property: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#property-form", "can't be blank")

      lv |> element("#edit-property-#{ctx.property.id}") |> render_click()
      lv |> form("#property-form", property: %{name: "Peril"}) |> render_submit()
      assert [%{name: "Peril"}] = Zones.list_properties(ctx.story)

      lv |> element("#edit-property-#{ctx.property.id}") |> render_click()
      lv |> element("#cancel-property") |> render_click()
      refute has_element?(lv, "#cancel-property")

      lv |> element("#delete-property-#{ctx.property.id}") |> render_click()
      assert Zones.list_properties(ctx.story) == []
    end

    test "zones are edited, cancelled, rejected and deleted", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/zones")

      lv
      |> form("#zone-form", zone: %{name: "Slums", values: %{"danger" => "lots"}})
      |> render_submit()

      assert has_element?(lv, "#zone-form #zone-value-danger[value='lots']")
      assert [_] = Zones.list_zones(ctx.story)

      lv |> element("#edit-zone-#{ctx.zone.id}") |> render_click()
      lv |> form("#zone-form", zone: %{name: "Harbour"}) |> render_submit()
      assert [%{name: "Harbour"}] = Zones.list_zones(ctx.story)

      lv |> element("#edit-zone-#{ctx.zone.id}") |> render_click()
      lv |> element("#cancel-zone") |> render_click()
      refute has_element?(lv, "#cancel-zone")

      lv |> element("#delete-zone-#{ctx.zone.id}") |> render_click()
      assert has_element?(lv, "#zones-empty")
    end
  end

  describe "periodic actions" do
    setup ctx do
      sheet_item_fixture(ctx.story, %{name: "Hunting"})
      tracker_fixture(ctx.story, %{"name" => "Hunger", "max_formula" => "5"})
      {:ok, _} = Zones.create_property(ctx.story, %{name: "Danger", default_value: 3})

      {:ok, action} =
        PeriodicActions.create_action(ctx.story, %{
          name: "Hunt",
          items: ["hunting"],
          difficulty_source: "zone",
          zone_property: "danger",
          default_difficulty: 2,
          success_tracker: "hunger",
          success_delta: 0
        })

      %{action: action}
    end

    test "actions are validated, edited and cancelled", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/actions")
      assert has_element?(lv, "#periodic-action-#{ctx.action.id}", "zone danger (default 2)")
      assert has_element?(lv, "#periodic-action-#{ctx.action.id}", "nothing")

      lv |> form("#periodic-action-form", action: %{name: ""}) |> render_change()
      assert has_element?(lv, "#periodic-action-form", "can't be blank")

      lv |> form("#periodic-action-form", action: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#periodic-action-form", "can't be blank")

      lv |> element("#edit-periodic-action-#{ctx.action.id}") |> render_click()
      lv |> form("#periodic-action-form", action: %{name: "Forage"}) |> render_submit()
      assert [%{name: "Forage"}] = PeriodicActions.list_actions(ctx.story)

      lv |> element("#edit-periodic-action-#{ctx.action.id}") |> render_click()
      lv |> element("#cancel-periodic-action") |> render_click()
      refute has_element?(lv, "#cancel-periodic-action")
    end
  end
end
