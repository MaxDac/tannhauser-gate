defmodule TannhauserGate.CharacterLifecycleTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Chat, Forum, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  describe "approval" do
    test "new characters are drafts in the default state and cannot play", ctx do
      character = draft_character_fixture(ctx.player, ctx.story)

      assert character.approval_status == "draft"
      assert character.state.name == "Active"
      refute Characters.can_play?(character)
      refute Characters.can_act_as?(ctx.player, character)
    end

    test "drafts are submitted, rejected with notes, resubmitted and approved", ctx do
      character = draft_character_fixture(ctx.player, ctx.story)

      assert {:ok, submitted} = Characters.submit_for_approval(character)
      assert submitted.approval_status == "submitted"
      assert [%{id: id}] = Characters.list_approval_queue(ctx.story.id)
      assert id == character.id

      assert {:error, :notes_required} = Characters.reject_character(submitted, ctx.master, " ")
      assert {:error, :unauthorized} = Characters.approve_character(submitted, user_fixture())

      assert {:ok, rejected} = Characters.reject_character(submitted, ctx.master, "Too strong")
      assert rejected.approval_status == "rejected"
      assert rejected.review_notes == "Too strong"
      assert rejected.reviewed_by_id == ctx.master.id
      assert Characters.list_approval_queue(ctx.story.id) == []

      assert {:ok, resubmitted} = Characters.submit_for_approval(rejected)
      assert {:ok, approved} = Characters.approve_character(resubmitted, ctx.gm)
      assert approved.approval_status == "approved"
      assert Characters.can_play?(approved)
      assert {:error, :invalid_status} = Characters.submit_for_approval(approved)
    end

    test "only approved, playable characters speak in chat", ctx do
      location = location_fixture(ctx.story)
      draft = draft_character_fixture(ctx.player, ctx.story)
      attrs = %{"character_id" => draft.id, "body" => "Hello"}

      assert {:error, :cannot_play} = Chat.create_message(ctx.player, location, attrs)

      {:ok, _} = Characters.approve_character(draft, ctx.master)
      assert {:ok, _} = Chat.create_message(ctx.player, location, attrs)
    end
  end

  describe "states" do
    test "every story gets a default playable state", ctx do
      assert [%{name: "Active", can_play: true}] = Characters.list_states(ctx.story)
    end

    test "a non-playable state blocks playing", ctx do
      character = character_fixture(ctx.player, ctx.story)
      {:ok, dead} = Characters.create_state(ctx.story, %{name: "Dead", can_play: false})

      assert Characters.can_play?(character)
      {:ok, _} = Characters.set_state(character, dead.id)
      character = Characters.get_character!(character.id)
      refute Characters.can_play?(character)
      assert [] = Characters.playable_characters(ctx.player, ctx.story)

      {:ok, _} = Characters.set_state(character, "")
      assert Characters.can_play?(Characters.get_character!(character.id))
    end

    test "states of other stories are rejected", ctx do
      character = character_fixture(ctx.player, ctx.story)
      [foreign] = Characters.list_states(story_fixture())
      assert {:error, :invalid_state} = Characters.set_state(character, foreign.id)
    end

    test "state names are unique per story", ctx do
      assert {:error, changeset} = Characters.create_state(ctx.story, %{name: "Active"})
      assert "already exists in this GDR" in errors_on(changeset).name
    end
  end

  describe "visibility" do
    test "full sheet for owner and masters, master notes for masters only", ctx do
      character = character_fixture(ctx.player, ctx.story)

      assert Characters.can_view_full_sheet?(ctx.player, character)
      assert Characters.can_view_full_sheet?(ctx.master, character)
      refute Characters.can_view_full_sheet?(user_fixture(), character)

      refute Characters.can_view_master_notes?(ctx.player, character)
      assert Characters.can_view_master_notes?(ctx.master, character)
    end

    test "players cannot write master notes", ctx do
      character = character_fixture(ctx.player, ctx.story)

      {:ok, updated} =
        Characters.update_character(character, %{
          "player_notes" => "Mine",
          "master_notes" => "Sneaky"
        })

      assert updated.player_notes == "Mine"
      assert is_nil(updated.master_notes)

      {:ok, updated} =
        Characters.update_character(updated, %{"master_notes" => "Secret"}, nil, master?: true)

      assert updated.master_notes == "Secret"
    end
  end

  describe "NPCs" do
    test "masters create approved NPCs beyond the one-per-user limit", ctx do
      _own = character_fixture(ctx.master, ctx.story)
      npc = npc_fixture(ctx.master, ctx.story)
      other = npc_fixture(ctx.master, ctx.story)

      assert npc.is_npc and npc.approval_status == "approved"
      assert Characters.can_act_as?(ctx.master, npc)
      assert Characters.can_act_as?(ctx.gm, other)
      refute Characters.can_act_as?(ctx.player, npc)

      ids = ctx.master |> Characters.playable_characters(ctx.story) |> Enum.map(& &1.id)
      assert npc.id in ids and other.id in ids
      assert Characters.active_character(ctx.master, ctx.story.id).is_npc == false
    end

    test "players cannot create NPCs and keep one character", ctx do
      assert {:error, :unauthorized} =
               Characters.create_npc(ctx.player, ctx.story, %{"name" => "Nope"})

      _ = character_fixture(ctx.player, ctx.story)

      assert {:error, changeset} =
               Characters.create_character(ctx.player, %{
                 "name" => "Second",
                 "story_id" => ctx.story.id
               })

      refute changeset.valid?
    end

    test "masters speak as NPCs, players cannot", ctx do
      location = location_fixture(ctx.story)
      npc = npc_fixture(ctx.master, ctx.story)
      attrs = %{"character_id" => npc.id, "body" => "Welcome"}

      assert {:ok, _} = Chat.create_message(ctx.gm, location, attrs)
      assert {:error, :unauthorized} = Chat.create_message(ctx.player, location, attrs)
    end
  end

  describe "dashboard filters and moderation helpers" do
    test "list_story_characters filters by approval, state and NPC", ctx do
      approved = character_fixture(ctx.player, ctx.story)
      draft = draft_character_fixture(user_fixture(), ctx.story)
      npc = npc_fixture(ctx.master, ctx.story)
      {:ok, _} = Characters.set_state(draft, "")

      ids = fn filters ->
        ctx.story.id |> Characters.list_story_characters(filters) |> Enum.map(& &1.id)
      end

      assert ids.(%{"approval_status" => "draft"}) == [draft.id]

      assert Enum.sort(ids.(%{"approval_status" => "approved"})) ==
               Enum.sort([approved.id, npc.id])

      assert ids.(%{"npc" => "true"}) == [npc.id]
      refute npc.id in ids.(%{"npc" => "false"})
      assert ids.(%{"state_id" => "none"}) == [draft.id]
    end

    test "story messages and posts are scoped to the story", ctx do
      character = character_fixture(ctx.player, ctx.story)
      message = message_fixture(ctx.player, location_fixture(ctx.story), character)
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))
      other_story = story_fixture()

      assert [%{id: id}] = Chat.list_story_messages(ctx.story.id)
      assert id == message.id
      assert Chat.get_story_message(other_story.id, message.id) == nil

      assert [post] = Forum.list_story_posts(ctx.story.id)
      assert post.topic_id == topic.id
      assert Forum.get_story_post(other_story.id, post.id) == nil
    end
  end
end
