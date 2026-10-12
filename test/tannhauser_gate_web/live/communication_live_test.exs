defmodule TannhauserGateWeb.CommunicationLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Forum, Mailbox, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    player = user_fixture()
    other = user_fixture()

    %{
      story: story,
      gm: gm,
      master: master,
      player: player,
      other: other,
      character: character_fixture(player, story),
      other_character: character_fixture(other, story)
    }
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp mail(ctx, subject \\ "Hello") do
    {:ok, msg} =
      Mailbox.send_message(ctx.player, ctx.story, %{
        "sender" => to_string(ctx.character.id),
        "recipient" => to_string(ctx.other_character.id),
        "subject" => subject,
        "body" => "Meet me at the bar."
      })

    msg
  end

  describe "mailbox" do
    test "composes a message to a character", ctx do
      {:ok, lv, _} =
        live(conn_for(ctx.player), ~p"/g/#{ctx.story}/mail/new?to=#{ctx.other_character.id}")

      assert has_element?(
               lv,
               "#mail-form option[value='#{ctx.other_character.id}'][selected]"
             )

      lv
      |> form("#mail-form",
        message: %{
          sender: ctx.character.id,
          recipient: ctx.other_character.id,
          subject: "Tonight",
          body: "At the bar."
        }
      )
      |> render_submit()

      assert [%{subject: "Tonight"}] = Mailbox.list_inbox(ctx.other, ctx.story)
      assert_redirect(lv, ~p"/g/#{ctx.story}/mail/sent")
    end

    test "players without a playable character cannot compose", ctx do
      {:ok, lv, _} = live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/mail/new")
      assert has_element?(lv, "#mail-no-sender")
      refute has_element?(lv, "#mail-form")
    end

    test "inbox, reading and the unread badge", ctx do
      msg = mail(ctx)
      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/mail")

      assert has_element?(lv, "#nav-mail-unread", "1")
      assert has_element?(lv, "#mail-message-#{msg.id}", "Hello")

      {:ok, show, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/mail/#{msg.id}")
      assert has_element?(show, "#mail-subject", "Hello")
      assert has_element?(show, "#mail-from", ctx.character.name)
      refute has_element?(show, "#nav-mail-unread")
      assert Mailbox.unread_count(ctx.other, ctx.story) == 0
    end

    test "replying prefills the form", ctx do
      msg = mail(ctx)
      conn = conn_for(ctx.other)
      {:ok, show, _} = live(conn, ~p"/g/#{ctx.story}/mail/#{msg.id}")

      {:ok, show, _} =
        show |> element("#reply-message") |> render_click() |> follow_redirect(conn)

      assert has_element?(show, "#mail-form input[value='Re: Hello']")

      show |> form("#mail-form", message: %{body: "Sure"}) |> render_submit()
      assert [%{reply_to_id: id}] = Mailbox.list_inbox(ctx.player, ctx.story)
      assert id == msg.id
    end

    test "bulk deletes from the inbox only", ctx do
      a = mail(ctx, "A")
      b = mail(ctx, "B")
      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/mail")

      lv
      |> form("#mail-list-form")
      |> render_submit(%{"ids" => [to_string(a.id), to_string(b.id)]})

      refute has_element?(lv, "#mail-message-#{a.id}")
      assert Mailbox.list_inbox(ctx.other, ctx.story) == []
      assert length(Mailbox.list_sent(ctx.player, ctx.story)) == 2
    end

    test "a new message updates the badge and flashes live", ctx do
      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/forum")
      refute has_element?(lv, "#nav-mail-unread")

      mail(ctx, "Psst")

      assert render(lv) =~ "New message from #{ctx.character.name}"
      assert has_element?(lv, "#nav-mail-unread", "1")
    end

    test "messages from other GDRs are not visible", ctx do
      msg = mail(ctx)
      {elsewhere, _} = gdr_fixture()

      assert {:error, {:live_redirect, _}} =
               live(conn_for(ctx.other), ~p"/g/#{elsewhere}/mail/#{msg.id}")
    end

    test "the character page links to compose a message", ctx do
      {:ok, lv, _} =
        live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{ctx.other_character}")

      assert has_element?(lv, "#send-message")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{ctx.character}")
      refute has_element?(lv, "#send-message")
    end

    test "masters message owners from the characters dashboard", ctx do
      npc = npc_fixture(ctx.master, ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/characters")

      assert has_element?(lv, "#message-#{ctx.character.id}")
      refute has_element?(lv, "#message-#{npc.id}")

      {:ok, compose, _} =
        live(conn_for(ctx.master), ~p"/g/#{ctx.story}/mail/new?to=#{ctx.character.id}")

      compose
      |> form("#mail-form",
        message: %{
          sender: npc.id,
          recipient: ctx.character.id,
          subject: "A job",
          body: "Come alone."
        }
      )
      |> render_submit()

      assert [%{sender_name: name}] = Mailbox.list_inbox(ctx.player, ctx.story)
      assert name == npc.name
    end
  end

  describe "forum" do
    test "on-game sections ask which character writes", ctx do
      section = section_fixture(ctx.story, %{on_game: true})
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum/sections/#{section.id}")

      assert has_element?(lv, "option[value='#{ctx.character.id}']")

      {:ok, lv, _} =
        live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/forum/sections/#{section.id}")

      assert has_element?(lv, "#forum-no-character")
    end

    test "hidden sections are not listed nor reachable", ctx do
      section = section_fixture(ctx.story, %{visibility: "masters"})

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum")
      refute has_element?(lv, "#forum-section-#{section.id}")

      assert {:error, {:live_redirect, _}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum/sections/#{section.id}")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/forum")
      assert has_element?(lv, "#forum-section-#{section.id}")
    end

    test "authors edit their posts", ctx do
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))
      [post] = Forum.list_posts(topic)

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/forum/topics/#{topic.id}")
      refute has_element?(lv, "#edit-post-#{post.id}")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum/topics/#{topic.id}")
      lv |> element("#edit-post-#{post.id}") |> render_click()

      lv
      |> form("#edit-post-form-#{post.id}", edit: %{body: "Rewritten"})
      |> render_submit()

      assert has_element?(lv, "#forum-posts", "Rewritten")
      refute has_element?(lv, "#edit-post-form-#{post.id}")
    end

    test "masters lock and pin topics", ctx do
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum/topics/#{topic.id}")
      refute has_element?(lv, "#toggle-lock")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/forum/topics/#{topic.id}")
      lv |> element("#toggle-lock") |> render_click()
      lv |> element("#toggle-pin") |> render_click()

      topic = Forum.get_topic!(topic.id)
      assert topic.locked and topic.pinned

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/forum/topics/#{topic.id}")
      assert has_element?(lv, "#topic-locked")
    end

    test "unread markers clear when the topic is read", ctx do
      section = section_fixture(ctx.story)
      topic = topic_fixture(ctx.player, section)

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/forum")
      assert has_element?(lv, "#section-unread-#{section.id}")

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/forum/sections/#{section.id}")
      assert has_element?(lv, "#topic-unread-#{topic.id}")

      {:ok, _, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/forum/topics/#{topic.id}")

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/forum")
      refute has_element?(lv, "#section-unread-#{section.id}")
    end

    test "the GDR admin edits a section's kind and visibility", ctx do
      section = section_fixture(ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/forum")

      lv |> element("#edit-section-#{section.id}") |> render_click()

      lv
      |> form("#section-form", section: %{on_game: "true", visibility: "approved"})
      |> render_submit()

      section = Forum.get_section!(section.id)
      assert section.on_game
      assert section.visibility == "approved"
      assert has_element?(lv, "#section-#{section.id}", "On game")
    end
  end
end
