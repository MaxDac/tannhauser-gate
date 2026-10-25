defmodule TannhauserGateWeb.EsitiLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Esiti, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp with_esiti(ctx) do
    story = enable_modules(ctx.story, [:esiti])
    Map.merge(ctx, %{story: story, character: character_fixture(ctx.player, story)})
  end

  defp file!(ctx, title \\ "Night at the warehouse") do
    {:ok, esito} =
      Esiti.create_esito(ctx.player, ctx.story, %{
        "character_id" => to_string(ctx.character.id),
        "title" => title,
        "body" => "I sneak in."
      })

    esito
  end

  describe "module disabled" do
    test "pages redirect and links are hidden", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/master")
      refute has_element?(lv, "#nav-esiti")
      refute has_element?(lv, "#master-esiti")
      refute has_element?(lv, ~s|a[href="/g/#{ctx.story.id}/gm/esiti"]|)

      for path <- [
            ~p"/g/#{ctx.story}/esiti",
            ~p"/g/#{ctx.story}/esiti/1",
            ~p"/g/#{ctx.story}/master/esiti"
          ] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.gm), path)
        assert to == ~p"/g/#{ctx.story}"
      end
    end
  end

  describe "player" do
    setup :with_esiti

    test "files a request and talks with the masters", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/esiti")
      assert has_element?(lv, "#nav-esiti")
      assert has_element?(lv, "#esiti-empty")
      assert has_element?(lv, "#esiti-limits")

      {:ok, show, _} =
        lv
        |> form("#esito-form",
          esito: %{
            character_id: ctx.character.id,
            title: "Crafting a blade",
            body: "I forge a **monoblade**."
          }
        )
        |> render_submit()
        |> follow_redirect(conn_for(ctx.player))

      assert has_element?(show, "#esito-title", "Crafting a blade")
      assert has_element?(show, "#esito-status", "Open")
      assert has_element?(show, "#esito-body strong", "monoblade")
      refute has_element?(show, "#esito-resolve")
      refute has_element?(show, "#claim-esito")

      show
      |> form("#esito-message-form", message: %{body: "Any news?"})
      |> render_submit()

      assert has_element?(show, "#esito-messages", "Any news?")

      [esito] = Esiti.list_user_esiti(ctx.player, ctx.story)
      {:ok, _} = Esiti.claim(ctx.master, ctx.story, esito)
      assert has_element?(show, "#esito-status", "In progress")

      show |> element("#withdraw-esito") |> render_click()
      assert has_element?(show, "#esito-status", "Closed")
      refute has_element?(show, "#esito-message-form")
    end

    test "sees the limit warning", ctx do
      {:ok, _} = Stories.update_story_as_gm(ctx.story, %{"esiti_max_open" => "1"})
      file!(ctx)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/esiti")
      assert has_element?(lv, "#esiti-limit-warning")

      lv
      |> form("#esito-form",
        esito: %{character_id: ctx.character.id, title: "More", body: "Again"}
      )
      |> render_submit()

      assert render(lv) =~ "open requests"
      assert length(Esiti.list_user_esiti(ctx.player, ctx.story)) == 1
    end

    test "can't open someone else's request", ctx do
      esito = file!(ctx)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/esiti/#{esito.id}")

      assert to == ~p"/g/#{ctx.story}/esiti"
    end
  end

  describe "master" do
    setup :with_esiti

    test "queue, claim and resolve with effects", ctx do
      esito = file!(ctx)
      file!(ctx, "Second")

      {:ok, dash, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      assert has_element?(dash, "#master-esiti-count", "2 open")
      assert has_element?(dash, "#nav-esiti-open", "2")

      {:ok, queue, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/esiti")
      assert has_element?(queue, "#esiti-#{esito.id}")
      queue |> element("#claim-#{esito.id}") |> render_click()
      assert has_element?(queue, "#release-#{esito.id}")

      queue |> element("#esiti-filter-mine") |> render_click()
      assert_patch(queue, ~p"/g/#{ctx.story}/master/esiti?status=mine")
      assert has_element?(queue, "#esiti-#{esito.id}")
      refute has_element?(queue, "#esiti-queue", "Second")

      {:ok, show, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/esiti/#{esito.id}")

      show
      |> form("#esito-message-form", message: %{body: "Roll Stealth.", as: "masters"})
      |> render_submit()

      assert has_element?(show, "#esito-messages", "The masters")

      show
      |> form("#esito-resolve-form",
        resolution: %{outcome: "You find the **crates**.", xp: "5", money: "40"}
      )
      |> render_submit()

      assert has_element?(show, "#esito-status", "Resolved")
      assert has_element?(show, "#esito-outcome-body strong", "crates")
      assert has_element?(show, "#esito-effects", "XP: +5")
      refute has_element?(show, "#esito-resolve")
      assert Characters.get_character!(ctx.character.id).balance == 40
    end

    test "a failing effect leaves the request open", ctx do
      esito = file!(ctx)
      {:ok, show, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/esiti/#{esito.id}")

      html =
        show
        |> form("#esito-resolve-form", resolution: %{outcome: "Fined.", money: "-100"})
        |> render_submit()

      assert html =~ "enough money"
      assert has_element?(show, "#esito-status", "Open")
    end

    test "rolls dice with the GDR system", ctx do
      esito = file!(ctx)
      {:ok, show, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/esiti/#{esito.id}")

      show
      |> form("#esito-resolve-form", resolution: %{outcome: "Rolled.", roll: "true"})
      |> render_change()

      show
      |> form("#esito-resolve-form",
        resolution: %{outcome: "Rolled.", roll: "true", dice: %{modifier: "1"}}
      )
      |> render_submit()

      assert has_element?(show, "#esito-dice")
      assert Esiti.get_esito(ctx.story, esito.id).dice_result["summary"]
    end

    test "GM sets the limits in the Esiti tab", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/esiti")

      lv
      |> form("#esiti-settings-form", story: %{esiti_max_open: "", esiti_min_xp: "20"})
      |> render_submit()

      story = Stories.get_story!(ctx.story.id)
      assert story.esiti_max_open == nil
      assert story.esiti_min_xp == 20
    end
  end
end
