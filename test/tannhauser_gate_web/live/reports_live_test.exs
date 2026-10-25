defmodule TannhauserGateWeb.ReportsLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Reports, Sanctions, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    player = user_fixture()
    other = user_fixture()
    room = location_fixture(story)

    %{
      story: story,
      gm: gm,
      master: master,
      player: player,
      other: other,
      room: room,
      character: character_fixture(player, story),
      other_character: character_fixture(other, story)
    }
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp with_reports(ctx), do: %{ctx | story: enable_modules(ctx.story, [:reports])}

  describe "module disabled" do
    test "no report links and the pages redirect", ctx do
      message_fixture(ctx.other, ctx.room, ctx.other_character)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")
      refute has_element?(lv, "[id^=report-message-]")

      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/master")
      refute has_element?(lv, "#master-reports")
      refute has_element?(lv, "#master-sanctions")

      for path <- [
            ~p"/g/#{ctx.story}/master/reports",
            ~p"/g/#{ctx.story}/master/sanctions",
            ~p"/g/#{ctx.story}/report?type=character&id=#{ctx.other_character.id}"
          ] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.gm), path)
        assert to == ~p"/g/#{ctx.story}"
      end
    end
  end

  describe "reporting" do
    setup :with_reports

    test "a player reports a chat entry from the room", ctx do
      message = message_fixture(ctx.other, ctx.room, ctx.other_character, "Rude words")
      own = message_fixture(ctx.player, ctx.room, ctx.character, "Mine")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")
      assert has_element?(lv, "#report-message-#{message.id}")
      refute has_element?(lv, "#report-message-#{own.id}")

      {:ok, lv, _} =
        lv
        |> element("#report-message-#{message.id}")
        |> render_click()
        |> follow_redirect(conn_for(ctx.player))

      assert has_element?(lv, "#report-preview", "Rude words")

      {:ok, _lv, html} =
        lv
        |> form("#report-form", report: %{category: "harassment", reason: "Insults"})
        |> render_submit()
        |> follow_redirect(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")

      assert html =~ "Report sent"
      assert [report] = Reports.list_reports(ctx.story)
      assert report.target_id == message.id
      assert report.reason == "Insults"
    end

    test "report links on the character sheet, mail and forum", ctx do
      {:ok, lv, _} =
        live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{ctx.other_character}")

      assert has_element?(lv, "#report-character")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{ctx.character}")
      refute has_element?(lv, "#report-character")

      section = section_fixture(ctx.story)
      topic = topic_fixture(ctx.other, section)
      [post] = TannhauserGate.Forum.list_posts(topic)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum/topics/#{topic}")
      assert has_element?(lv, "#report-post-#{post.id}")

      {:ok, letter} =
        TannhauserGate.Mailbox.send_message(ctx.other, ctx.story, %{
          "sender" => to_string(ctx.other_character.id),
          "recipient" => to_string(ctx.character.id),
          "subject" => "Threat",
          "body" => "Watch your back."
        })

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/mail/#{letter}")
      assert has_element?(lv, "#report-mail")
    end

    test "duplicate reports are rejected with a flash", ctx do
      path = ~p"/g/#{ctx.story}/report?type=character&id=#{ctx.other_character.id}"
      {:ok, lv, _} = live(conn_for(ctx.player), path)
      lv |> form("#report-form", report: %{category: "metagame"}) |> render_submit()

      assert {:error, {:live_redirect, %{flash: %{"error" => error}}}} =
               live(conn_for(ctx.player), path)

      assert error =~ "already reported"
    end
  end

  describe "the queue" do
    setup :with_reports

    test "masters resolve with deletion and dismiss", ctx do
      message = message_fixture(ctx.other, ctx.room, ctx.other_character, "Spam!")

      {:ok, chat} =
        Reports.create_report(ctx.player, ctx.story, %{
          "target_type" => "chat",
          "target_id" => message.id,
          "category" => "spam"
        })

      {:ok, char} =
        Reports.create_report(ctx.player, ctx.story, %{
          "target_type" => "character",
          "target_id" => ctx.other_character.id,
          "category" => "rules"
        })

      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/master")
      assert has_element?(lv, "#master-reports-count", "2 open")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/reports")
      assert has_element?(lv, "#reports-#{chat.id}")

      lv
      |> form("#resolve-form-#{chat.id}",
        resolution: %{resolution_notes: "Removed", delete_content: "true"}
      )
      |> render_submit(%{"resolution" => %{"status" => "resolved"}})

      refute has_element?(lv, "#reports-#{chat.id}")
      assert TannhauserGate.Chat.get_story_message(ctx.story.id, message.id) == nil

      lv
      |> form("#resolve-form-#{char.id}")
      |> render_submit(%{"resolution" => %{"status" => "dismissed"}})

      assert has_element?(lv, "#reports-empty")

      lv |> form("#reports-filters", filters: %{status: "all"}) |> render_change()
      assert has_element?(lv, "#report-#{chat.id}-status", "Resolved")
      assert has_element?(lv, "#report-#{char.id}-status", "Dismissed")
      assert has_element?(lv, "#sanction-author-#{chat.id}")
    end

    test "players and masters without can_moderate cannot reach it", ctx do
      assert {:error, {:redirect, _}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/reports")

      {:ok, _} = Stories.set_master_permission(ctx.story, ctx.master.id, :can_moderate, false)

      for path <- [
            ~p"/g/#{ctx.story}/master/reports",
            ~p"/g/#{ctx.story}/master/sanctions",
            ~p"/g/#{ctx.story}/master/moderation"
          ] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.master), path)
        assert to == ~p"/g/#{ctx.story}"
      end

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      refute has_element?(lv, "#master-moderation")
      refute has_element?(lv, "#master-reports")
      assert has_element?(lv, "#master-zones")

      message = message_fixture(ctx.other, ctx.room, ctx.other_character)
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")
      refute has_element?(lv, "#delete-message-#{message.id}")
    end
  end

  describe "sanctions" do
    setup :with_reports

    test "issuing from the page, prefilled, then revoking", ctx do
      {:ok, lv, _} =
        live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/sanctions?user_id=#{ctx.player.id}")

      assert has_element?(lv, "#sanction-form input[value='#{ctx.player.username}']")

      lv |> form("#sanction-form", sanction: %{kind: "mute"}) |> render_change()

      lv
      |> form("#sanction-form",
        sanction: %{kind: "mute", duration: "72", reason: "Flooding the chat"}
      )
      |> render_submit()

      assert [sanction] = Sanctions.list_sanctions(ctx.story)
      assert sanction.kind == "mute"
      assert has_element?(lv, "#sanctions-#{sanction.id}", "Flooding the chat")

      lv |> element("#revoke-sanction-#{sanction.id}") |> render_click()
      assert has_element?(lv, "#sanction-#{sanction.id}-status", "Revoked")
      refute Sanctions.muted?(ctx.player, ctx.story)
    end

    test "staff cannot be sanctioned", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/sanctions")

      html =
        lv
        |> form("#sanction-form",
          sanction: %{username: ctx.gm.username, kind: "ban", reason: "x"}
        )
        |> render_submit()

      assert html =~ "cannot be sanctioned"
      assert Sanctions.list_sanctions(ctx.story) == []
    end

    test "a banned user cannot enter the GDR", ctx do
      {:ok, _} =
        Sanctions.issue(ctx.master, ctx.story, %{
          "user_id" => ctx.player.id,
          "kind" => "ban",
          "duration" => "168",
          "reason" => "Cheating"
        })

      assert {:error, {:redirect, %{to: "/gdrs", flash: %{"error" => error}}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}")

      assert error =~ "banned"
      assert error =~ "Cheating"

      assert {:error, {:redirect, %{to: "/gdrs"}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.room}")

      assert {:ok, _lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}")

      {:ok, story} = Stories.set_module_enabled(ctx.story, :reports, false)
      assert {:ok, _lv, _} = live(conn_for(ctx.player), ~p"/g/#{story}")
    end

    test "a muted user gets a friendly error and a notice on the next page", ctx do
      {:ok, _} =
        Sanctions.issue(ctx.master, ctx.story, %{
          "user_id" => ctx.player.id,
          "kind" => "mute",
          "duration" => "24",
          "reason" => "Spam"
        })

      {:ok, _lv, html} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      assert html =~ "muted"

      section = section_fixture(ctx.story)
      topic = topic_fixture(ctx.other, section)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum/topics/#{topic}")

      html = lv |> form("#post-form-0", post: %{body: "Let me speak"}) |> render_submit()
      assert html =~ "muted"
    end
  end

  describe "GM masters tab" do
    test "the GDR admin toggles a master permission", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm?tab=masters")
      assert has_element?(lv, "#master-#{ctx.master.id}-can_moderate[checked]")

      lv |> element("#master-#{ctx.master.id}-can_moderate") |> render_click()

      refute Stories.can?(ctx.master, ctx.story, :can_moderate)
      refute has_element?(lv, "#master-#{ctx.master.id}-can_moderate[checked]")
      assert has_element?(lv, "#master-#{ctx.master.id}-can_award_xp[checked]")
    end
  end
end
