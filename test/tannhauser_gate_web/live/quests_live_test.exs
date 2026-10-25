defmodule TannhauserGateWeb.QuestsLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Quests, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp with_quests(ctx) do
    story = enable_modules(ctx.story, [:quests])
    Map.merge(ctx, %{story: story, character: character_fixture(ctx.player, story)})
  end

  defp quest!(ctx, attrs) do
    {:ok, quest} =
      Quests.create_quest(
        ctx.master,
        ctx.story,
        Enum.into(attrs, %{"title" => "Quest", "held_on" => "2026-10-01"})
      )

    {:ok, _} =
      Quests.add_participant(ctx.master, ctx.story, quest, %{
        "character_id" => to_string(ctx.character.id)
      })

    quest
  end

  describe "module disabled" do
    test "pages redirect and links are hidden", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/master")
      refute has_element?(lv, "#nav-quests")
      refute has_element?(lv, "#master-quests")

      for path <- [~p"/g/#{ctx.story}/quests", ~p"/g/#{ctx.story}/master/quests"] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.gm), path)
        assert to == ~p"/g/#{ctx.story}"
      end
    end
  end

  describe "registry" do
    setup :with_quests

    test "players see public quests only; masters all of them", ctx do
      public = quest!(ctx, %{"title" => "The blackout", "summary" => "**Lights** out"})
      secret = quest!(ctx, %{"title" => "The mole", "visibility" => "masters"})

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/quests")
      assert has_element?(lv, "#nav-quests")
      assert has_element?(lv, "#quest-#{public.id}", "The blackout")
      assert has_element?(lv, "#quest-#{public.id}-summary strong", "Lights")
      assert has_element?(lv, "#quest-#{public.id}-participant-#{ctx.character.id}")
      refute has_element?(lv, "#quest-#{secret.id}")
      refute has_element?(lv, "#quests-manage")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/quests")
      assert has_element?(lv, "#quest-#{secret.id}-masters-only")

      # The character sheet lists the quests the viewer can see.
      {:ok, sheet, _} =
        live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      assert has_element?(sheet, "#character-quest-#{public.id}")
      refute has_element?(sheet, "#character-quest-#{secret.id}")

      {:ok, sheet, _} =
        live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      assert has_element?(sheet, "#character-quest-#{secret.id}")
    end

    test "masters link the chat log of the quest", ctx do
      room = location_fixture(ctx.story)

      quest =
        quest!(ctx, %{
          "location_id" => to_string(room.id),
          "log_from" => "2026-10-01T20:00",
          "log_to" => "2026-10-01T23:30"
        })

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/quests")

      link = "#quest-#{quest.id}-log[href^='/g/#{ctx.story.id}/master/chat-log?']"
      assert has_element?(lv, link <> "[href*='location_id=#{room.id}']")
      assert has_element?(lv, link <> "[href*='from=2026-10-01']")
      assert has_element?(lv, link <> "[href*='to=2026-10-01']")
    end

    test "players can't open the master page", ctx do
      assert {:error, {:redirect, _}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/quests")
    end
  end

  describe "master" do
    setup :with_quests

    test "records a quest, adds participants and awards them once", ctx do
      {:ok, dash, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      assert has_element?(dash, "#master-quests")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/quests")
      assert has_element?(lv, "#quests-empty")

      lv
      |> form("#quest-form",
        quest: %{title: "Pier raid", summary: "Boom", held_on: "2026-10-03", visibility: "public"}
      )
      |> render_submit()

      [quest] = Quests.list_quests(ctx.story, ctx.master)
      assert has_element?(lv, "#master-quest-#{quest.id}")
      assert has_element?(lv, "#quest-participants")

      lv
      |> form("#participant-form",
        participant: %{character_id: ctx.character.id, xp: "3", money: "25", note: "Brave"}
      )
      |> render_submit()

      [p] = Quests.get_quest(ctx.story, quest.id).participants
      assert has_element?(lv, "#participant-#{p.id}", "25")

      lv |> element("#apply-quest-rewards") |> render_click()
      assert has_element?(lv, "#quest-rewarded")
      refute has_element?(lv, "#apply-quest-rewards")
      refute has_element?(lv, "#participant-form")
      assert Characters.get_character!(ctx.character.id).balance == 25

      # Applying again (e.g. from a stale page) is refused.
      assert {:error, :already_rewarded} =
               Quests.apply_rewards(ctx.master, ctx.story, quest)
    end
  end
end
