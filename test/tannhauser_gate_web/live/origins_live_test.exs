defmodule TannhauserGateWeb.OriginsLiveTest do
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

  defp with_origins(ctx) do
    story = enable_modules(ctx.story, [:origins])
    body = sheet_item_fixture(story, %{name: "Body"})
    {:ok, group} = Origins.create_group(story, %{name: "Origin", required: true})
    {:ok, human} = Origins.create_option(story, %{group_id: group.id, name: "Human"})

    {:ok, replicant} =
      Origins.create_option(story, %{
        group_id: group.id,
        name: "Replicant",
        description: "An **Echo**.",
        requires_approval: true,
        bonuses: %{"body" => 1}
      })

    Map.merge(ctx, %{story: story, body: body, group: group, human: human, replicant: replicant})
  end

  describe "GM origins page" do
    test "is hidden and redirects when the module is disabled", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm")
      refute has_element?(lv, "#gm-tab-origins")

      assert {:error, {:redirect, %{to: to}}} =
               live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/origins")

      assert to == ~p"/g/#{ctx.story}"
    end

    test "masters who are not GDR admins cannot reach it", ctx do
      story = enable_modules(ctx.story, [:origins])

      assert {:error, {:redirect, %{to: to}}} =
               live(conn_for(ctx.master), ~p"/g/#{story}/gm/origins")

      assert to == ~p"/g/#{story}"
    end

    test "the GDR admin manages groups and options", ctx do
      story = enable_modules(ctx.story, [:origins])
      sheet_item_fixture(story, %{name: "Body"})

      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{story}/gm/origins")
      assert has_element?(lv, "#gm-tab-origins")
      assert has_element?(lv, "#origin-groups-empty")

      lv
      |> form("#origin-group-form", group: %{name: "Race", required: "true"})
      |> render_submit()

      [group] = Origins.list_groups(story)
      assert group.required
      assert has_element?(lv, "#origin-group-#{group.id}", "Race")

      lv
      |> form("#origin-option-form",
        option: %{group_id: group.id, name: "Elf", bonuses: %{"body" => "nope"}}
      )
      |> render_submit()

      assert has_element?(lv, "#origin-option-form", "body must be a whole number")

      lv
      |> form("#origin-option-form",
        option: %{
          group_id: group.id,
          name: "Elf",
          description: "Pointy ears",
          requires_approval: "true",
          bonuses: %{"body" => "-1"}
        }
      )
      |> render_submit()

      [%{options: [option]}] = Origins.list_groups(story)
      assert option.bonuses == %{"body" => -1}
      assert option.requires_approval
      assert has_element?(lv, "#origin-option-bonuses-#{option.id}", "−1 body")

      lv |> element("#edit-origin-option-#{option.id}") |> render_click()
      lv |> form("#origin-option-form", option: %{name: "High elf"}) |> render_submit()
      assert has_element?(lv, "#origin-option-#{option.id}", "High elf")

      lv |> element("#delete-origin-option-#{option.id}") |> render_click()
      refute has_element?(lv, "#origin-option-#{option.id}")

      lv |> element("#delete-origin-group-#{group.id}") |> render_click()
      assert Origins.list_groups(story) == []
    end
  end

  describe "creation wizard" do
    test "has an origins step with required groups", ctx do
      ctx = with_origins(ctx)
      conn = conn_for(ctx.player)
      {:ok, lv, _} = live(conn, ~p"/g/#{ctx.story}/characters/new")

      assert has_element?(lv, "#wizard-step-origins")

      lv |> form("#character-form", character: %{name: "Roy"}) |> render_submit()
      assert has_element?(lv, "#origins-step")
      assert has_element?(lv, "#origin-option-approval-#{ctx.replicant.id}")

      lv |> form("#character-form") |> render_submit()
      assert has_element?(lv, "#step-errors", "Choose your Origin.")

      lv
      |> form("#character-form",
        character: %{origins: %{"#{ctx.group.id}" => "#{ctx.replicant.id}"}}
      )
      |> render_submit()

      refute has_element?(lv, "#origins-step")
      # Attribute step, then review.
      lv |> form("#character-form") |> render_submit()
      assert has_element?(lv, "#review-origins", "Replicant")

      {:ok, _show, html} =
        lv |> form("#character-form") |> render_submit() |> follow_redirect(conn)

      assert html =~ "Character created"
      [character] = Characters.list_user_characters(ctx.player)
      assert Origins.choices(character) == %{ctx.group.id => ctx.replicant.id}
    end

    test "has no origins step when the module is disabled", ctx do
      ctx = with_origins(ctx)
      {:ok, _} = Stories.set_module_enabled(ctx.story, :origins, false)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/new")
      refute has_element?(lv, "#wizard-step-origins")
    end

    test "approved owners cannot change origins, masters can", ctx do
      ctx = with_origins(ctx)

      character =
        character_fixture(ctx.player, ctx.story, %{
          "origins" => %{"#{ctx.group.id}" => "#{ctx.human.id}"}
        })

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}/edit")
      refute has_element?(lv, "#origins-step")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{character}/edit")
      assert has_element?(lv, "#origins-step")

      lv
      |> form("#character-form",
        character: %{origins: %{"#{ctx.group.id}" => "#{ctx.replicant.id}"}}
      )
      |> render_submit()

      assert Origins.choices(character) == %{ctx.group.id => ctx.replicant.id}
    end
  end

  describe "sheet" do
    test "shows origins publicly and bonuses on the full sheet", ctx do
      ctx = with_origins(ctx)

      character =
        character_fixture(ctx.player, ctx.story, %{
          "traits" => %{"#{ctx.body.id}" => "3"},
          "origins" => %{"#{ctx.group.id}" => "#{ctx.replicant.id}"}
        })

      {:ok, lv, _} = live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/characters/#{character}")
      assert has_element?(lv, "#character-origin-option-#{ctx.replicant.id}", "Replicant")
      assert has_element?(lv, "#character-origin-#{ctx.group.id} strong", "Replicant")
      refute has_element?(lv, "#character-origin-bonuses-#{ctx.replicant.id}")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}")
      assert has_element?(lv, "#character-origin-bonuses-#{ctx.replicant.id}", "+1 body")
      assert has_element?(lv, "#trait-value-#{ctx.body.id}", "4")
      assert has_element?(lv, "#trait-bonus-#{ctx.body.id}", "+1")
    end

    test "players must choose required origins before submitting", ctx do
      ctx = with_origins(ctx)
      character = draft_character_fixture(ctx.player, ctx.story)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}")
      lv |> element("#submit-for-approval") |> render_click()

      assert render(lv) =~ "Choose every required origin"
      assert Characters.get_character!(character.id).approval_status == "draft"
    end

    test "the master dashboard lists origins and flags restricted ones", ctx do
      ctx = with_origins(ctx)

      character =
        draft_character_fixture(ctx.player, ctx.story, %{
          "origins" => %{"#{ctx.group.id}" => "#{ctx.replicant.id}"}
        })

      {:ok, _} = Characters.submit_for_approval(character)

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/characters")
      assert has_element?(lv, "#queue-origins-#{character.id} .badge-warning", "Replicant")
      assert has_element?(lv, "#character-origins-#{character.id}", "Replicant")
    end
  end
end
