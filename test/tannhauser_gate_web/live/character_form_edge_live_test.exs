defmodule TannhauserGateWeb.CharacterFormEdgeLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Origins, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp new_wizard(ctx) do
    {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/new")
    lv
  end

  # Moves through the remaining wizard steps keeping the current values.
  defp to_review(lv, attempts \\ 6)
  defp to_review(_lv, 0), do: flunk("the wizard never reached the review step")

  defp to_review(lv, attempts) do
    if has_element?(lv, "#review-step") do
      lv
    else
      lv |> form("#character-form") |> render_submit()
      to_review(lv, attempts - 1)
    end
  end

  defp with_origins(ctx, group_attrs) do
    story = enable_modules(ctx.story, [:origins])
    {:ok, group} = Origins.create_group(story, Map.merge(%{name: "Origin"}, group_attrs))

    {:ok, option} =
      Origins.create_option(
        story,
        %{group_id: group.id, name: "Spacer"},
        "/uploads/spacer.png"
      )

    Map.merge(ctx, %{story: story, group: group, option: option})
  end

  describe "mount" do
    test "editing a character of another GDR redirects with an error", ctx do
      {other_story, _gm} = gdr_fixture()
      character = character_fixture(ctx.player, other_story, %{"name" => "Elsewhere"})

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}/edit")

      assert to == ~p"/g/#{ctx.story}/characters"
      assert flash["error"] == "That character does not exist in this GDR."
    end
  end

  describe "creation wizard" do
    test "rejects trait values that are not whole numbers", ctx do
      item = sheet_item_fixture(ctx.story, %{name: "Grit", description: "Staying power"})
      lv = new_wizard(ctx)

      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()
      assert has_element?(lv, "#sheet-attribute", "Staying power")

      lv
      |> form("#character-form", character: %{traits: %{"#{item.id}" => "lots"}})
      |> render_submit()

      assert has_element?(lv, "#step-errors", "must be a whole number")
      assert has_element?(lv, "#sheet-attribute")
    end

    test "shows the distribution budget of the step", ctx do
      [one, two] =
        for name <- ~w(Body Mind),
            do: sheet_item_fixture(ctx.story, %{name: name, min_value: 1, max_value: 5})

      category_fixture(ctx.story, "attribute", %{
        "creation_mode" => "distribution",
        "creation_distribution" => "3,2",
        "starting_value" => "1"
      })

      lv = new_wizard(ctx)
      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()

      assert has_element?(lv, "#budget-attribute", "3, 2")
      assert has_element?(lv, "#budget-attribute", "Still to assign")

      lv
      |> form("#character-form",
        character: %{traits: %{"#{one.id}" => "3", "#{two.id}" => "2"}}
      )
      |> render_change()

      refute has_element?(lv, "#budget-attribute", "Still to assign")
    end

    test "optional origin groups offer a None choice", ctx do
      ctx = with_origins(ctx, %{required: false, description: "Where you came from"})
      lv = new_wizard(ctx)

      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()

      assert has_element?(lv, "#origin-group-#{ctx.group.id}", "Where you came from")
      assert has_element?(lv, "#origin-#{ctx.group.id}-none[checked]")
      assert has_element?(lv, "#origin-group-#{ctx.group.id} img[src='/uploads/spacer.png']")

      to_review(lv)
      assert has_element?(lv, "#review-origins", "—")
    end

    test "rejects an origin option that does not belong to the group", ctx do
      ctx = with_origins(ctx, %{required: true})
      lv = new_wizard(ctx)

      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()
      assert has_element?(lv, "#origins-step")

      lv
      |> form("#character-form")
      |> render_submit(%{character: %{origins: %{"#{ctx.group.id}" => "-1"}}})

      assert has_element?(lv, "#step-errors", "Origin: choose one of its options")
      assert has_element?(lv, "#origins-step")
    end

    test "the final save reports a blank name and stays on the review", ctx do
      lv = new_wizard(ctx)
      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()
      to_review(lv)

      lv |> form("#character-form", character: %{name: ""}) |> render_submit()

      assert has_element?(lv, "#step-errors", "Name can't be blank")
      assert has_element?(lv, "#review-step")
      assert Characters.list_user_characters(ctx.player) == []
    end

    test "the final save reports trait values changed after their step", ctx do
      item = sheet_item_fixture(ctx.story, %{name: "Grit", min_value: 0, max_value: 5})
      lv = new_wizard(ctx)
      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()
      to_review(lv)

      lv
      |> form("#character-form")
      |> render_change(%{character: %{traits: %{"#{item.id}" => "9"}}})

      lv |> form("#character-form") |> render_submit()

      assert has_element?(lv, "#step-errors", "Grit")
      assert Characters.list_user_characters(ctx.player) == []
    end

    test "the final save reports an invalid origin choice", ctx do
      ctx = with_origins(ctx, %{required: false})
      lv = new_wizard(ctx)
      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()
      to_review(lv)

      lv
      |> form("#character-form")
      |> render_submit(%{character: %{origins: %{"#{ctx.group.id}" => "-1"}}})

      assert has_element?(lv, "#step-errors", "choose one of its options")
      assert Characters.list_user_characters(ctx.player) == []
    end

    test "rejects avatars of unsupported types", ctx do
      lv = new_wizard(ctx)

      avatar =
        file_input(lv, "#character-form", :avatar, [
          %{name: "notes.txt", content: "not an image", type: "text/plain"}
        ])

      render_upload(avatar, "notes.txt")

      assert has_element?(lv, "#avatar-errors", "Unsupported file type")
    end

    test "allows a single avatar", ctx do
      lv = new_wizard(ctx)

      avatar =
        file_input(lv, "#character-form", :avatar, [
          %{name: "a.png", content: "png", type: "image/png"},
          %{name: "b.png", content: "png", type: "image/png"}
        ])

      render_upload(avatar, "a.png")

      assert has_element?(lv, "#avatar-errors", "Only one image is allowed")
    end
  end

  describe "editing" do
    test "a blank name keeps the form open with an error", ctx do
      character = character_fixture(ctx.player, ctx.story, %{"name" => "Roy"})
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}/edit")

      lv |> form("#character-form", character: %{name: ""}) |> render_submit()

      assert has_element?(lv, "#character-form", "can't be blank")
      assert Characters.get_character!(character.id).name == "Roy"
    end

    test "masters get trait and origin errors back on the form", ctx do
      ctx = with_origins(ctx, %{required: false})
      item = sheet_item_fixture(ctx.story, %{name: "Grit", min_value: 0, max_value: 5})
      character = character_fixture(ctx.player, ctx.story, %{"name" => "Roy"})

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{character}/edit")

      lv
      |> form("#character-form", character: %{traits: %{"#{item.id}" => "9"}})
      |> render_submit()

      assert has_element?(lv, "#character-form", "Grit")

      lv
      |> form("#character-form", character: %{traits: %{"#{item.id}" => "2"}})
      |> render_submit(%{character: %{origins: %{"#{ctx.group.id}" => "-1"}}})

      assert has_element?(lv, "#origins-step", "choose one of its options")
      assert Origins.choices(character) == %{}
    end
  end

  describe "new NPC" do
    test "a blank name keeps the form open", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/npcs/new")

      lv |> form("#character-form", character: %{name: ""}) |> render_submit()

      assert has_element?(lv, "#character-form", "can't be blank")
    end

    test "a master demoted after opening the page cannot create the NPC", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/npcs/new")
      :ok = Stories.remove_master(ctx.story, ctx.master.id)

      lv |> form("#character-form", character: %{name: "Bartender"}) |> render_submit()

      assert has_element?(lv, "#flash-error", "Only the GDR masters can create NPCs.")
    end
  end
end
