defmodule TannhauserGate.ModerationContextsEdgeCasesTest do
  @moduledoc """
  Edge cases (permissions, error branches, nil clauses and labels) of the
  quests, sanctions, reports and bookings contexts.
  """
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Boards, Bookings, Chat, Forum, Items, Quests, Reports, Sanctions, Stories}
  alias TannhauserGate.Quests.Quest
  alias TannhauserGate.Sanctions.Sanction

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

  describe "quests" do
    setup ctx do
      story = enable_modules(ctx.story, [:quests, :items])

      {:ok, quest} =
        Quests.create_quest(ctx.master, story, %{"title" => "Blackout", "held_on" => "2026-10-01"})

      %{story: story, quest: quest}
    end

    defp add_participant!(ctx, attrs) do
      {:ok, participant} =
        Quests.add_participant(
          ctx.master,
          ctx.story,
          ctx.quest,
          Map.put(attrs, "character_id", to_string(ctx.character.id))
        )

      participant
    end

    test "module checks and nil clauses", ctx do
      assert Quests.enabled?(ctx.story.id)
      refute Quests.enabled?(nil)

      {plain, _} = gdr_fixture()

      assert {:error, :module_disabled} =
               Quests.create_quest(ctx.master, plain, %{"title" => "x", "held_on" => "2026-01-01"})

      assert Quests.visible?(%Quest{visibility: "public"}, ctx.story, nil)
      refute Quests.visible?(%Quest{visibility: "masters"}, ctx.story, ctx.player)
      assert Quests.get_quest(ctx.story, "abc") == nil
      assert Quests.get_quest(ctx.story, nil) == nil
      assert Quests.visibility_label("other") == "other"
    end

    test "participants are updated and removed by the masters only", ctx do
      participant = add_participant!(ctx, %{"xp" => "5"})

      assert {:error, :unauthorized} =
               Quests.update_participant(ctx.player, ctx.story, ctx.quest, participant.id, %{})

      assert {:ok, updated} =
               Quests.update_participant(ctx.master, ctx.story, ctx.quest, participant.id, %{
                 "xp" => "9"
               })

      assert updated.xp == 9

      assert {:error, :not_found} =
               Quests.update_participant(ctx.master, ctx.story, ctx.quest, "abc", %{})

      assert {:error, :item_not_found} =
               Quests.update_participant(ctx.master, ctx.story, ctx.quest, participant.id, %{
                 "item_id" => "999999"
               })

      assert {:error, :not_found} =
               Quests.remove_participant(ctx.master, ctx.story, ctx.quest, "999999")

      assert {:ok, _} =
               Quests.remove_participant(ctx.master, ctx.story, ctx.quest, participant.id)

      assert Quests.get_quest(ctx.story, ctx.quest.id).participants == []
    end

    test "unknown characters and items without quantity are rejected", ctx do
      assert {:error, :character_not_found} =
               Quests.add_participant(ctx.master, ctx.story, ctx.quest, %{"character_id" => "x"})

      {:ok, item} = Items.create_item(ctx.story, %{"name" => "Medkit", "price" => 5})

      assert {:error, changeset} =
               Quests.add_participant(ctx.master, ctx.story, ctx.quest, %{
                 "character_id" => to_string(ctx.character.id),
                 "item_id" => to_string(item.id),
                 "item_quantity" => "0"
               })

      assert "must be at least 1 for the item" in errors_on(changeset).item_quantity
    end

    test "deleting a quest and rewarding a deleted one", ctx do
      assert {:error, :unauthorized} = Quests.delete_quest(ctx.player, ctx.story, ctx.quest)
      assert {:ok, _} = Quests.delete_quest(ctx.master, ctx.story, ctx.quest)
      assert Quests.get_quest(ctx.story, ctx.quest.id) == nil

      assert {:error, :quest_not_found} = Quests.apply_rewards(ctx.master, ctx.story, ctx.quest)
    end

    test "error messages" do
      for reason <- [
            :module_disabled,
            :unauthorized,
            :quest_not_found,
            :character_not_found,
            :item_not_found,
            :not_found,
            :already_rewarded,
            :invalid_reward,
            :invalid_amount,
            :not_enough_items,
            "boom"
          ] do
        assert is_binary(Quests.error_message(reason))
      end
    end
  end

  describe "sanctions" do
    setup ctx, do: %{story: enable_modules(ctx.story, [:reports])}

    defp issue(ctx, attrs) do
      Sanctions.issue(
        ctx.master,
        ctx.story,
        Enum.into(attrs, %{"user_id" => ctx.player.id, "kind" => "mute", "reason" => "Rude"})
      )
    end

    test "nil clauses and defaults", ctx do
      refute Sanctions.enabled?(nil)
      assert Sanctions.active_sanction(nil, ctx.story, "mute") == nil
      assert Sanctions.check_not_muted(ctx.player, nil) == :ok
      assert Sanctions.muted_message(ctx.player, ctx.story) =~ "right now"
      assert Sanctions.format(nil) == "—"
      assert Sanctions.pop_unseen(nil, ctx.story) == []
      assert %Ecto.Changeset{} = Sanctions.change_sanction()
    end

    test "a ban silences the user", ctx do
      assert {:ok, ban} = issue(ctx, %{"kind" => "ban", "duration" => "permanent"})
      assert ban.ends_at == nil
      assert Sanctions.muted_message(ctx.player, ctx.story) =~ "banned"
    end

    test "targets and invalid attributes", ctx do
      assert {:error, :user_not_found} = issue(ctx, %{"user_id" => "abc"})

      assert {:error, :user_not_found} =
               Sanctions.issue(ctx.master, ctx.story, %{"kind" => "mute", "reason" => "x"})

      assert {:error, %Ecto.Changeset{} = changeset} = issue(ctx, %{"kind" => "bogus"})
      assert Sanctions.error_message(changeset) == "Check the sanction form."
    end

    test "end dates: explicit, invalid duration and string", ctx do
      at = DateTime.utc_now(:second) |> DateTime.add(7200)
      assert {:ok, sanction} = issue(ctx, %{"ends_at" => at})
      assert sanction.ends_at == at

      assert {:ok, permanent} = issue(ctx, %{"duration" => "soon"})
      assert permanent.ends_at == nil

      later = DateTime.utc_now(:second) |> DateTime.add(3600)
      assert {:ok, explicit} = issue(ctx, %{"ends_at" => DateTime.to_iso8601(later)})
      assert explicit.ends_at == later
    end

    test "a sanction links a report of the story; filters and lookups", ctx do
      {:ok, report} =
        Reports.create_report(ctx.other, ctx.story, %{
          "target_type" => "character",
          "target_id" => ctx.character.id,
          "category" => "spam"
        })

      assert {:ok, sanction} =
               issue(ctx, %{"kind" => "warning", "report_id" => to_string(report.id)})

      assert sanction.report_id == report.id
      assert Sanctions.status_label(sanction) == "Recorded"

      assert [%{id: id}] = Sanctions.list_sanctions(ctx.story, %{"kind" => "warning"})
      assert id == sanction.id
      assert Sanctions.list_sanctions(ctx.story, %{"kind" => "ban"}) == []
      assert Sanctions.get_sanction(ctx.story, "abc") == nil
    end

    test "error messages" do
      for reason <- [
            :module_disabled,
            :unauthorized,
            :user_not_found,
            :staff,
            :not_found,
            :already_revoked,
            %Ecto.Changeset{},
            :boom
          ] do
        assert is_binary(Sanctions.error_message(reason))
      end

      assert Sanctions.status_label(%Sanction{kind: "warning"}) == "Recorded"
    end
  end

  describe "reports" do
    setup ctx, do: %{story: enable_modules(ctx.story, [:reports, :boards])}

    defp report!(ctx, type, id) do
      {:ok, report} =
        Reports.create_report(ctx.player, ctx.story, %{
          "target_type" => type,
          "target_id" => id,
          "category" => "harassment"
        })

      report
    end

    defp resolve(ctx, report, attrs \\ %{"delete_content" => "true"}) do
      Reports.resolve(ctx.master, ctx.story, report, Map.put_new(attrs, "status", "resolved"))
    end

    test "labels, nil clauses and invalid ids", ctx do
      refute Reports.enabled?(nil)
      assert Reports.category_label("unknown") == "unknown"
      assert Reports.target_type_label("other") == "other"
      assert Reports.status_label("other") == "other"
      assert %Ecto.Changeset{} = Reports.change_report()
      assert Reports.get_report(ctx.story, "abc") == nil

      for id <- ["abc", nil] do
        assert {:error, :target_not_found} =
                 Reports.create_report(ctx.player, ctx.story, %{
                   "target_type" => "character",
                   "target_id" => id,
                   "category" => "spam"
                 })
      end
    end

    test "filters by target type", ctx do
      report = report!(ctx, "character", ctx.other_character.id)
      assert [%{id: id}] = Reports.list_reports(ctx.story, %{"target_type" => "character"})
      assert id == report.id
      assert Reports.list_reports(ctx.story, %{"target_type" => "chat"}) == []

      assert %Ecto.Changeset{} = Reports.change_resolution(report)
    end

    test "resolving deletes forum posts and notices", ctx do
      topic = topic_fixture(ctx.other, section_fixture(ctx.story))
      [post] = Forum.list_posts(topic)
      post_report = report!(ctx, "forum_post", post.id)

      assert {:ok, %{content_deleted: true}} = resolve(ctx, post_report)
      assert Forum.get_story_post(ctx.story.id, post.id) == nil

      room = location_fixture(ctx.story)

      {:ok, board} =
        Boards.create_board(ctx.master, ctx.story, %{"name" => "W", "location_id" => room.id})

      {:ok, notice} =
        Boards.post_notice(ctx.other, ctx.story, board, %{
          "character_id" => to_string(ctx.other_character.id),
          "body" => "Buy my stuff"
        })

      notice_report = report!(ctx, "notice", notice.id)
      assert {:ok, %{content_deleted: true}} = resolve(ctx, notice_report)
      assert Boards.get_notice(ctx.story, notice.id) == nil

      character_report = report!(ctx, "character", ctx.other_character.id)
      assert {:ok, %{content_deleted: false}} = resolve(ctx, character_report)
    end

    test "content already gone is not deleted twice", ctx do
      room = location_fixture(ctx.story)
      message = message_fixture(ctx.other, room, ctx.other_character, "Rude")
      chat_report = report!(ctx, "chat", message.id)
      {:ok, _} = Chat.delete_message(message)
      assert {:ok, %{content_deleted: false}} = resolve(ctx, chat_report)

      topic = topic_fixture(ctx.other, section_fixture(ctx.story))
      [post] = Forum.list_posts(topic)
      post_report = report!(ctx, "forum_post", post.id)
      {:ok, _} = Forum.delete_post(post)
      assert {:ok, %{content_deleted: false}} = resolve(ctx, post_report)

      {:ok, board} =
        Boards.create_board(ctx.master, ctx.story, %{"name" => "W", "location_id" => room.id})

      {:ok, notice} =
        Boards.post_notice(ctx.other, ctx.story, board, %{
          "character_id" => to_string(ctx.other_character.id),
          "body" => "Buy"
        })

      notice_report = report!(ctx, "notice", notice.id)
      {:ok, _} = Boards.delete_notice(ctx.other, ctx.story, notice)
      assert {:ok, %{content_deleted: false}} = resolve(ctx, notice_report)
    end

    test "an invalid resolution is a changeset error", ctx do
      report = report!(ctx, "character", ctx.other_character.id)

      assert {:error, %Ecto.Changeset{} = changeset} =
               resolve(ctx, report, %{"status" => "bogus"})

      assert Reports.error_message(changeset) == "Check the report form."
    end

    test "error messages" do
      for reason <- [
            :module_disabled,
            :unauthorized,
            :invalid_target,
            :target_not_found,
            :own_content,
            :rate_limited,
            :duplicate,
            :not_found,
            :not_open,
            %Ecto.Changeset{},
            :boom
          ] do
        assert is_binary(Reports.error_message(reason))
      end
    end
  end

  describe "bookings" do
    setup ctx, do: %{location: location_fixture(ctx.story, %{private: true})}

    defp book(ctx, attrs) do
      now = DateTime.utc_now(:second)

      Bookings.create_booking(
        ctx.player,
        ctx.location,
        Enum.into(attrs, %{
          "character_id" => ctx.character.id,
          "starts_at" => now |> DateTime.add(3600) |> DateTime.to_iso8601(),
          "ends_at" => now |> DateTime.add(7200) |> DateTime.to_iso8601()
        }),
        now
      )
    end

    test "nil and invalid inputs", ctx do
      refute Bookings.can_access?(ctx.player, nil)
      refute Bookings.can_access?(nil, ctx.location)
      assert %Ecto.Changeset{} = Bookings.change_booking()

      assert {:error, :character_not_found} = book(ctx, %{"character_id" => nil})
      assert {:error, :character_not_found} = book(ctx, %{"character_id" => "abc"})
      assert {:error, :character_not_found} = book(ctx, %{"character_id" => "999999999"})
    end

    test "invalid invitee ids are ignored", ctx do
      assert {:ok, booking} = book(ctx, %{"invitee_ids" => ["abc"]})
      assert booking.invited_characters == []
    end

    test "error messages", ctx do
      assert {:error, %Ecto.Changeset{} = changeset} =
               book(ctx, %{"ends_at" => DateTime.utc_now() |> DateTime.to_iso8601()})

      assert Bookings.error_message(changeset) =~ "Ends at"

      for reason <- [
            :not_private,
            :overlap,
            :cannot_play,
            :invalid_invitee,
            :unauthorized,
            :character_not_found,
            :boom
          ] do
        assert is_binary(Bookings.error_message(reason))
      end
    end
  end
end
