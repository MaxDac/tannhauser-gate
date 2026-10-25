defmodule TannhauserGate.ReportsSanctionsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Boards, Chat, Forum, Mailbox, Reports, Sanctions, Stories}
  alias TannhauserGate.Sanctions.Sanction

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    story = enable_modules(story, [:reports])
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

  defp report(ctx, user, type, id, attrs \\ %{}) do
    Reports.create_report(
      user,
      ctx.story,
      Enum.into(attrs, %{"target_type" => type, "target_id" => id, "category" => "harassment"})
    )
  end

  defp mail(ctx, user, from, to) do
    Mailbox.send_message(user, ctx.story, %{
      "sender" => to_string(from.id),
      "recipient" => to_string(to.id),
      "subject" => "Hello",
      "body" => "Meet me at the bar."
    })
  end

  defp sanction(ctx, target, kind, attrs \\ %{}) do
    Sanctions.issue(
      ctx.master,
      ctx.story,
      Enum.into(attrs, %{
        "user_id" => target.id,
        "kind" => kind,
        "reason" => "Breaking the rules",
        "duration" => "24"
      })
    )
  end

  describe "reports" do
    test "chat entries: snapshot, author, duplicate guard and own content", ctx do
      message = message_fixture(ctx.other, ctx.room, ctx.other_character, "You are all idiots")

      assert {:ok, report} = report(ctx, ctx.player, "chat", message.id, %{"reason" => "Rude"})
      assert report.status == "open"
      assert report.content_snapshot == "You are all idiots"
      assert report.target_user_id == ctx.other.id
      assert Reports.reported?(ctx.player, "chat", message.id)

      assert {:error, :duplicate} = report(ctx, ctx.player, "chat", message.id)
      assert {:error, :own_content} = report(ctx, ctx.other, "chat", message.id)

      # The snapshot survives the deletion of the message.
      {:ok, _} = Chat.delete_message(message)
      assert Reports.get_report(ctx.story, report.id).content_snapshot == "You are all idiots"
    end

    test "whispers can be reported only by who can read them", ctx do
      story = enable_modules(ctx.story, [:chat_rp])
      third = user_fixture()
      character_fixture(third, story)

      {:ok, whisper} =
        Chat.create_message(ctx.other, ctx.room, %{
          "character_id" => ctx.other_character.id,
          "kind" => "whisper",
          "recipient_character_id" => ctx.character.id,
          "body" => "psst"
        })

      assert {:error, :target_not_found} =
               report(%{ctx | story: story}, third, "chat", whisper.id)

      assert {:ok, _} = report(%{ctx | story: story}, ctx.player, "chat", whisper.id)
    end

    test "forum posts: visibility of the section", ctx do
      open = section_fixture(ctx.story)
      masters_only = section_fixture(ctx.story, %{visibility: "masters"})
      topic = topic_fixture(ctx.other, open)
      [post] = Forum.list_posts(topic)

      {:ok, hidden_topic} =
        Forum.create_topic(ctx.master, masters_only, %{"title" => "x", "body" => "secret"})

      [hidden] = Forum.list_posts(hidden_topic)

      assert {:ok, report} = report(ctx, ctx.player, "forum_post", post.id)
      assert report.content_snapshot == "The opening post"
      assert {:error, :target_not_found} = report(ctx, ctx.player, "forum_post", hidden.id)
      assert {:ok, _} = report(ctx, ctx.gm, "forum_post", hidden.id)
    end

    test "mail: only a letter the user received", ctx do
      third = user_fixture()
      character_fixture(third, ctx.story)
      {:ok, letter} = mail(ctx, ctx.other, ctx.other_character, ctx.character)

      assert {:error, :target_not_found} = report(ctx, third, "mail", letter.id)
      # The sender only has it among the sent letters.
      assert {:error, :target_not_found} = report(ctx, ctx.other, "mail", letter.id)
      assert {:ok, report} = report(ctx, ctx.player, "mail", letter.id)
      assert report.content_snapshot =~ "Meet me at the bar."
    end

    test "notices need the boards module and a visible board", ctx do
      {:ok, board} =
        Boards.create_board(ctx.master, enable_modules(ctx.story, [:boards]), %{
          "name" => "Wall",
          "location_id" => ctx.room.id
        })

      story = Stories.get_story!(ctx.story.id)

      {:ok, notice} =
        Boards.post_notice(ctx.other, story, board, %{
          "character_id" => to_string(ctx.other_character.id),
          "body" => "Selling stolen goods"
        })

      assert {:ok, _} = report(%{ctx | story: story}, ctx.player, "notice", notice.id)

      {:ok, story} = Stories.set_module_enabled(story, :boards, false)

      assert {:error, :target_not_found} =
               report(%{ctx | story: story}, ctx.gm, "notice", notice.id)
    end

    test "characters: approved ones, never your own", ctx do
      draft = draft_character_fixture(user_fixture(), ctx.story)

      assert {:ok, report} = report(ctx, ctx.player, "character", ctx.other_character.id)
      assert report.target_label =~ ctx.other_character.name
      assert {:error, :target_not_found} = report(ctx, ctx.player, "character", draft.id)
      assert {:ok, _} = report(ctx, ctx.master, "character", draft.id)
      assert {:error, :own_content} = report(ctx, ctx.player, "character", ctx.character.id)
    end

    test "content of another GDR cannot be reported", ctx do
      {other_story, _} = gdr_fixture()
      foreign_user = user_fixture()
      foreign_character = character_fixture(foreign_user, other_story)
      foreign_room = location_fixture(other_story)
      message = message_fixture(foreign_user, foreign_room, foreign_character)

      assert {:error, :target_not_found} = report(ctx, ctx.player, "chat", message.id)

      assert {:error, :target_not_found} =
               report(ctx, ctx.player, "character", foreign_character.id)

      assert {:error, :invalid_target} = report(ctx, ctx.player, "story", ctx.story.id)
    end

    test "nothing can be reported when the module is off", ctx do
      {:ok, story} = Stories.set_module_enabled(ctx.story, :reports, false)

      assert {:error, :module_disabled} =
               report(%{ctx | story: story}, ctx.player, "character", ctx.other_character.id)
    end

    test "the queue: filters, resolve with deletion and dismiss", ctx do
      message = message_fixture(ctx.other, ctx.room, ctx.other_character, "spam spam")
      {:ok, chat} = report(ctx, ctx.player, "chat", message.id, %{"category" => "spam"})
      {:ok, char} = report(ctx, ctx.player, "character", ctx.other_character.id)

      assert Reports.open_count(ctx.story) == 2
      assert [%{id: id}] = Reports.list_reports(ctx.story, %{"category" => "spam"})
      assert id == chat.id

      assert {:error, :unauthorized} =
               Reports.resolve(ctx.player, ctx.story, chat, %{"status" => "resolved"})

      assert {:ok, resolved} =
               Reports.resolve(ctx.master, ctx.story, chat, %{
                 "status" => "resolved",
                 "resolution_notes" => "Deleted",
                 "delete_content" => "true"
               })

      assert resolved.status == "resolved"
      assert resolved.content_deleted
      assert resolved.handled_by_id == ctx.master.id
      assert Chat.get_story_message(ctx.story.id, message.id) == nil

      assert {:error, :not_open} =
               Reports.resolve(ctx.master, ctx.story, resolved, %{"status" => "dismissed"})

      assert {:ok, %{status: "dismissed", content_deleted: false}} =
               Reports.resolve(ctx.master, ctx.story, char, %{"status" => "dismissed"})

      assert Reports.open_count(ctx.story) == 0
      assert Reports.list_reports(ctx.story) == []
      assert length(Reports.list_reports(ctx.story, %{"status" => "all"})) == 2

      # Once handled, the same target can be reported again.
      assert {:ok, _} = report(ctx, ctx.player, "character", ctx.other_character.id)
    end
  end

  describe "sanctions" do
    test "a mute blocks every write at the context level", ctx do
      section = section_fixture(ctx.story)
      topic = topic_fixture(ctx.other, section)
      assert {:ok, %Sanction{kind: "mute"}} = sanction(ctx, ctx.player, "mute")

      assert Sanctions.muted?(ctx.player, ctx.story)

      assert {:error, :muted} =
               Chat.create_message(ctx.player, ctx.room, %{
                 "character_id" => ctx.character.id,
                 "body" => "hi"
               })

      assert {:error, :muted} =
               Chat.create_message(ctx.player, ctx.room, %{
                 "character_id" => ctx.character.id,
                 "kind" => "ooc",
                 "body" => "hi"
               })

      assert {:error, :muted} =
               Chat.roll_dice(ctx.player, ctx.room, %{"character_id" => ctx.character.id})

      assert {:error, :muted} = Forum.create_post(ctx.player, topic, %{"body" => "x"})

      assert {:error, :muted} =
               Forum.create_topic(ctx.player, section, %{"title" => "t", "body" => "b"})

      assert {:error, :muted} = mail(ctx, ctx.player, ctx.character, ctx.other_character)

      # Others are not affected.
      assert {:ok, _} = mail(ctx, ctx.other, ctx.other_character, ctx.character)
    end

    test "the sanctioned user gets a letter from the masters", ctx do
      {:ok, _} = sanction(ctx, ctx.player, "warning")

      assert [letter] = Mailbox.list_inbox(ctx.player, ctx.story)
      assert letter.subject =~ "warning"
      assert letter.body =~ "Breaking the rules"
    end

    test "staff cannot be sanctioned and players cannot sanction", ctx do
      assert {:error, :staff} = sanction(ctx, ctx.master, "ban")
      assert {:error, :staff} = sanction(ctx, ctx.gm, "ban")
      assert {:error, :staff} = sanction(ctx, admin_fixture(), "mute")

      assert {:error, :unauthorized} =
               Sanctions.issue(ctx.player, ctx.story, %{
                 "user_id" => ctx.other.id,
                 "kind" => "ban",
                 "reason" => "x"
               })

      assert {:error, :user_not_found} =
               Sanctions.issue(ctx.master, ctx.story, %{
                 "username" => "nobody-here",
                 "kind" => "ban",
                 "reason" => "x"
               })
    end

    test "expired and revoked sanctions are inactive", ctx do
      {:ok, ban} = sanction(ctx, ctx.player, "ban", %{"duration" => "permanent"})
      assert ban.ends_at == nil
      assert Sanctions.active_ban(ctx.player, ctx.story)
      # A ban also mutes.
      assert Sanctions.muted?(ctx.player, ctx.story)

      assert {:error, :unauthorized} = Sanctions.revoke(ctx.player, ctx.story, ban)
      assert {:ok, revoked} = Sanctions.revoke(ctx.master, ctx.story, ban)
      assert revoked.revoked_by_id == ctx.master.id
      assert {:error, :already_revoked} = Sanctions.revoke(ctx.master, ctx.story, revoked)
      refute Sanctions.active_ban(ctx.player, ctx.story)

      {:ok, mute} = sanction(ctx, ctx.other, "mute")
      assert Sanctions.muted?(ctx.other, ctx.story)

      mute
      |> Ecto.Changeset.change(
        starts_at: DateTime.add(DateTime.utc_now(:second), -7200),
        ends_at: DateTime.add(DateTime.utc_now(:second), -60)
      )
      |> Repo.update!()

      refute Sanctions.muted?(ctx.other, ctx.story)

      assert [_] = Sanctions.list_sanctions(ctx.story, %{"user_id" => to_string(ctx.other.id)})
      assert [] = Sanctions.list_sanctions(ctx.story, %{"status" => "active"})
    end

    test "sanctions have no effect when the module is off", ctx do
      {:ok, _} = sanction(ctx, ctx.player, "mute")
      {:ok, story} = Stories.set_module_enabled(ctx.story, :reports, false)

      refute Sanctions.muted?(ctx.player, story)

      assert {:ok, _} =
               Chat.create_message(ctx.player, ctx.room, %{
                 "character_id" => ctx.character.id,
                 "body" => "free again"
               })

      assert {:error, :module_disabled} = sanction(%{ctx | story: story}, ctx.other, "ban")
    end
  end

  describe "staff permissions" do
    test "default to true; the matrix by role", ctx do
      [row] = Stories.list_master_rows(ctx.story)
      for perm <- Stories.StoryMaster.permissions(), do: assert(Map.fetch!(row, perm))

      for perm <- Stories.StoryMaster.permissions() do
        assert Stories.can?(ctx.gm, ctx.story, perm)
        assert Stories.can?(admin_fixture(), ctx.story, perm)
        assert Stories.can?(ctx.master, ctx.story, perm)
        refute Stories.can?(ctx.player, ctx.story, perm)
      end
    end

    test "a master without can_moderate cannot delete chat messages nor resolve reports",
         ctx do
      {:ok, _} = Stories.set_master_permission(ctx.story, ctx.master.id, :can_moderate, false)
      message = message_fixture(ctx.other, ctx.room, ctx.other_character)

      refute Stories.can?(ctx.master, ctx.story, :can_moderate)
      assert Stories.can?(ctx.master, ctx.story, :can_manage_world)
      assert Stories.master?(ctx.master, ctx.story)

      assert {:error, :unauthorized} = Chat.delete_message(ctx.master, message)
      assert {:ok, _} = Chat.delete_message(ctx.gm, message)

      {:ok, report} = report(ctx, ctx.player, "character", ctx.other_character.id)

      assert {:error, :unauthorized} =
               Reports.resolve(ctx.master, ctx.story, report, %{"status" => "dismissed"})

      assert {:error, :unauthorized} = sanction(ctx, ctx.player, "warning")
    end

    test "other permissions gate their contexts", ctx do
      {:ok, _} =
        Stories.set_master_permission(ctx.story, ctx.master.id, :can_approve_characters, false)

      {:ok, _} = Stories.set_master_permission(ctx.story, ctx.master.id, :can_award_xp, false)
      draft = draft_character_fixture(user_fixture(), ctx.story)

      assert {:error, :unauthorized} =
               TannhauserGate.Characters.approve_character(draft, ctx.master)

      assert {:error, :unauthorized} =
               TannhauserGate.Experience.award(ctx.master, ctx.character, 5, "Good scene")

      assert {:error, :not_found} =
               Stories.set_master_permission(ctx.story, ctx.player.id, :can_moderate, false)
    end
  end
end
