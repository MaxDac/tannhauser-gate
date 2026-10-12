defmodule TannhauserGate.CommunicationTest do
  use TannhauserGate.DataCase, async: true

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

  defp mail(user, story, sender, recipient, subject \\ "Hello") do
    Mailbox.send_message(user, story, %{
      "sender" => to_string(sender),
      "recipient" => to_string(recipient),
      "subject" => subject,
      "body" => "Meet me at the bar."
    })
  end

  describe "mailbox" do
    test "players write between characters; the recipient reads", ctx do
      Mailbox.subscribe(ctx.story.id)
      {:ok, msg} = mail(ctx.player, ctx.story, ctx.character.id, ctx.other_character.id)

      assert msg.sender_name == ctx.character.name
      assert_receive {:mailbox, :received, %{id: id}} when id == msg.id

      assert [%{id: ^id}] = Mailbox.list_inbox(ctx.other, ctx.story)
      assert [%{id: ^id}] = Mailbox.list_sent(ctx.player, ctx.story)
      assert Mailbox.list_inbox(ctx.player, ctx.story) == []
      assert Mailbox.unread_count(ctx.other, ctx.story) == 1

      {:ok, _} = Mailbox.mark_read(ctx.other, ctx.story, msg)
      assert Mailbox.unread_count(ctx.other, ctx.story) == 0
    end

    test "the sender must be a character the user can play", ctx do
      assert {:error, changeset} =
               mail(ctx.player, ctx.story, ctx.other_character.id, ctx.character.id)

      assert "is not a character you can play" in errors_on(changeset).sender

      drafter = user_fixture()
      draft = draft_character_fixture(drafter, ctx.story)
      assert {:error, _} = mail(drafter, ctx.story, draft.id, ctx.other_character.id)
    end

    test "players only write to approved characters", ctx do
      draft = draft_character_fixture(user_fixture(), ctx.story)
      assert {:error, changeset} = mail(ctx.player, ctx.story, ctx.character.id, draft.id)
      assert errors_on(changeset).recipient != []
    end

    test "messages are scoped to the GDR", ctx do
      {elsewhere, _gm} = gdr_fixture()
      foreign = character_fixture(user_fixture(), elsewhere)
      assert {:error, _} = mail(ctx.player, ctx.story, ctx.character.id, foreign.id)

      {:ok, msg} = mail(ctx.player, ctx.story, ctx.character.id, ctx.other_character.id)
      assert Mailbox.get_message(ctx.other, elsewhere, msg.id) == nil
      assert Mailbox.get_message(ctx.gm, ctx.story, msg.id) == nil
    end

    test "masters write as NPCs and share the masters' mailbox", ctx do
      npc = npc_fixture(ctx.master, ctx.story)
      {:ok, _} = mail(ctx.master, ctx.story, npc.id, ctx.character.id, "From the NPC")
      assert [%{sender_name: name}] = Mailbox.list_inbox(ctx.player, ctx.story)
      assert name == npc.name

      {:ok, to_masters} = mail(ctx.player, ctx.story, ctx.character.id, "masters", "Help")
      assert Mailbox.recipient_name(to_masters) == "The masters"
      assert Enum.any?(Mailbox.list_inbox(ctx.gm, ctx.story), &(&1.id == to_masters.id))
      assert Enum.any?(Mailbox.list_inbox(ctx.master, ctx.story), &(&1.id == to_masters.id))

      {:ok, reply} = mail(ctx.gm, ctx.story, "masters", ctx.character.id, "Re: Help")
      assert reply.from_masters
      assert Enum.any?(Mailbox.list_sent(ctx.master, ctx.story), &(&1.id == reply.id))

      assert {:error, _} = mail(ctx.gm, ctx.story, "masters", "masters")
      assert {:error, _} = mail(ctx.player, ctx.story, "masters", ctx.other_character.id)
    end

    test "deletion is per side, and bulk", ctx do
      {:ok, a} = mail(ctx.player, ctx.story, ctx.character.id, ctx.other_character.id, "A")
      {:ok, b} = mail(ctx.player, ctx.story, ctx.character.id, ctx.other_character.id, "B")

      assert Mailbox.delete_messages(ctx.other, ctx.story, [a.id, b.id], :inbox) == 2
      assert Mailbox.list_inbox(ctx.other, ctx.story) == []
      assert length(Mailbox.list_sent(ctx.player, ctx.story)) == 2

      # cannot delete someone else's messages
      assert Mailbox.delete_messages(ctx.other, ctx.story, [a.id], :sent) == 0

      assert Mailbox.delete_messages(ctx.player, ctx.story, [to_string(a.id)], :sent) == 1
      assert [%{id: id}] = Mailbox.list_sent(ctx.player, ctx.story)
      assert id == b.id
    end

    test "reply_attrs swaps the sides", ctx do
      {:ok, msg} = mail(ctx.player, ctx.story, ctx.character.id, ctx.other_character.id)
      attrs = Mailbox.reply_attrs(ctx.other, ctx.story, msg)

      assert attrs["sender"] == to_string(ctx.other_character.id)
      assert attrs["recipient"] == to_string(ctx.character.id)
      assert attrs["subject"] == "Re: Hello"

      {:ok, reply} = Mailbox.send_message(ctx.other, ctx.story, %{attrs | "body" => "Sure"})
      assert reply.reply_to_id == msg.id
    end
  end

  describe "forum permissions" do
    test "visibility restricts sections", ctx do
      all = section_fixture(ctx.story)
      approved = section_fixture(ctx.story, %{visibility: "approved"})
      masters = section_fixture(ctx.story, %{visibility: "masters"})
      newcomer = user_fixture()

      visible = fn user ->
        user |> Forum.list_visible_sections(ctx.story) |> Enum.map(& &1.section.id)
      end

      assert visible.(newcomer) == [all.id]
      assert Enum.sort(visible.(ctx.player)) == Enum.sort([all.id, approved.id])
      assert length(visible.(ctx.master)) == 3
      assert masters.id in visible.(ctx.gm)

      assert {:error, :unauthorized} =
               Forum.create_topic(newcomer, approved, %{"title" => "Hi", "body" => "x"})
    end

    test "on-game sections are written as a character that can play", ctx do
      section = section_fixture(ctx.story, %{on_game: true})

      assert {:error, changeset} =
               Forum.create_topic(ctx.player, section, %{"title" => "In", "body" => "x"})

      assert errors_on(changeset).character_id != []

      assert {:error, _} =
               Forum.create_topic(ctx.player, section, %{
                 "title" => "In",
                 "body" => "x",
                 "character_id" => ctx.other_character.id
               })

      {:ok, topic} =
        Forum.create_topic(ctx.player, section, %{
          "title" => "In",
          "body" => "x",
          "character_id" => to_string(ctx.character.id)
        })

      topic = Forum.get_topic!(topic.id)
      assert topic.character_id == ctx.character.id
      assert Forum.author_name(topic) == ctx.character.name
    end

    test "off-game posts are authored by the user", ctx do
      section = section_fixture(ctx.story)

      {:ok, topic} =
        Forum.create_topic(ctx.player, section, %{
          "title" => "Out",
          "body" => "x",
          "character_id" => ctx.character.id
        })

      assert Forum.get_topic!(topic.id).character_id == nil
    end

    test "authors edit and delete their own posts; masters moderate", ctx do
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))
      {:ok, post} = Forum.create_post(ctx.other, topic, %{"body" => "Reply"})

      assert {:error, :unauthorized} =
               Forum.update_post(ctx.player, ctx.story, post, %{"body" => "x"})

      {:ok, edited} = Forum.update_post(ctx.other, ctx.story, post, %{"body" => "Edited"})
      assert edited.edited_at
      {:ok, _} = Forum.update_post(ctx.master, ctx.story, edited, %{"body" => "Moderated"})

      assert {:error, :unauthorized} =
               Forum.set_topic_flags(ctx.player, ctx.story, topic, %{locked: true})

      {:ok, locked} =
        Forum.set_topic_flags(ctx.master, ctx.story, topic, %{locked: true, pinned: true})

      assert locked.locked and locked.pinned

      assert {:error, :locked} = Forum.create_post(ctx.other, locked, %{"body" => "Late"})
      assert {:ok, _} = Forum.create_post(ctx.master, locked, %{"body" => "Closing"})

      assert {:error, :unauthorized} = Forum.delete_topic(ctx.other, ctx.story, locked)
      assert {:ok, _} = Forum.delete_topic(ctx.player, ctx.story, locked)
    end

    test "unread markers per topic and section", ctx do
      section = section_fixture(ctx.story)
      topic = topic_fixture(ctx.player, section)

      unread = fn user ->
        [%{unread_count: count}] = Forum.list_visible_sections(user, ctx.story)
        count
      end

      assert unread.(ctx.player) == 0
      assert unread.(ctx.other) == 1
      assert [%{unread: true}] = Forum.list_topics(section, ctx.other)

      Forum.mark_topic_read(ctx.other, topic)
      assert unread.(ctx.other) == 0

      {:ok, _} = Forum.create_post(ctx.player, topic, %{"body" => "More"})
      assert unread.(ctx.other) == 1
      assert [%{unread: false}] = Forum.list_topics(section, ctx.player)
    end
  end
end
