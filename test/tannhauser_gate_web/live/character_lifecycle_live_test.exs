defmodule TannhauserGateWeb.CharacterLifecycleLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Chat, Forum, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  describe "character sheet" do
    test "the owner submits a draft and resubmits after rejection", ctx do
      character = draft_character_fixture(ctx.player, ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}")

      assert has_element?(lv, "#character-approval-status", "Draft")
      refute has_element?(lv, "#master-panel")

      lv |> element("#submit-for-approval") |> render_click()
      assert has_element?(lv, "#character-approval-status", "Awaiting approval")
      refute has_element?(lv, "#submit-for-approval")

      {:ok, _} =
        Characters.reject_character(Characters.get_character!(character.id), ctx.master, "Why?")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/#{character}")
      assert has_element?(lv, "#character-review-notes", "Why?")
      assert has_element?(lv, "#submit-for-approval")
    end

    test "masters approve, reject and set the state from the sheet", ctx do
      character = draft_character_fixture(ctx.player, ctx.story)
      {:ok, dead} = Characters.create_state(ctx.story, %{name: "Dead", can_play: false})
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{character}")

      assert has_element?(lv, "#master-panel")

      lv |> form("#review-form", review: %{notes: ""}) |> render_submit(%{decision: "reject"})
      assert render(lv) =~ "Explain why the character is rejected."

      lv
      |> form("#review-form", review: %{notes: "Welcome"})
      |> render_submit(%{decision: "approve"})

      assert has_element?(lv, "#character-approval-status", "Approved")

      lv |> form("#state-form", character_state: %{state_id: dead.id}) |> render_submit()
      assert has_element?(lv, "#character-state", "Dead")
      refute Characters.can_play?(Characters.get_character!(character.id))
    end

    test "visibility of values and notes depends on the viewer", ctx do
      item = sheet_item_fixture(ctx.story)

      character =
        character_fixture(ctx.player, ctx.story, %{
          "off_game_info" => "Plays on weekends",
          "player_notes" => "My secret plan",
          "traits" => %{to_string(item.id) => "3"}
        })

      {:ok, _} =
        Characters.update_character(character, %{"master_notes" => "Watch out"}, nil,
          master?: true
        )

      path = ~p"/g/#{ctx.story}/characters/#{character}"

      {:ok, lv, _} = live(conn_for(user_fixture()), path)
      assert has_element?(lv, "#character-off-game", "Plays on weekends")
      refute has_element?(lv, "#trait-value-#{item.id}")
      refute has_element?(lv, "#character-player-notes")
      refute has_element?(lv, "#character-master-notes")

      {:ok, lv, _} = live(conn_for(ctx.player), path)
      assert has_element?(lv, "#trait-value-#{item.id}")
      assert has_element?(lv, "#character-player-notes", "My secret plan")
      refute has_element?(lv, "#character-master-notes")

      {:ok, lv, _} = live(conn_for(ctx.master), path)
      assert has_element?(lv, "#trait-value-#{item.id}")
      assert has_element?(lv, "#character-master-notes", "Watch out")
    end
  end

  describe "chat rooms" do
    test "unapproved characters cannot speak", ctx do
      character = draft_character_fixture(ctx.player, ctx.story)
      location = location_fixture(ctx.story)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{location}")
      assert has_element?(lv, "#cannot-play-notice", character.name)
      refute has_element?(lv, "#message-form-0")
    end

    test "masters speak as NPCs and delete messages", ctx do
      npc = npc_fixture(ctx.master, ctx.story)
      location = location_fixture(ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/rooms/#{location}")

      lv
      |> form("#message-form-0", message: %{character_id: npc.id, body: "The bar is closed"})
      |> render_submit()

      [message] = Chat.list_messages(location.id)
      assert message.character_id == npc.id
      assert has_element?(lv, "#delete-message-#{message.id}")

      lv |> element("#delete-message-#{message.id}") |> render_click()
      assert Chat.list_messages(location.id) == []
    end

    test "players see no delete buttons", ctx do
      character = character_fixture(ctx.player, ctx.story)
      location = location_fixture(ctx.story)
      message = message_fixture(ctx.player, location, character)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{location}")
      refute has_element?(lv, "#delete-message-#{message.id}")
    end
  end

  describe "master tools" do
    test "players cannot reach the master pages", ctx do
      conn = conn_for(ctx.player)

      for path <- [
            ~p"/g/#{ctx.story}/master/characters",
            ~p"/g/#{ctx.story}/master/moderation",
            ~p"/g/#{ctx.story}/master/npcs/new"
          ] do
        assert {:error, {_kind, %{to: _}}} = live(conn, path)
      end
    end

    test "the master home shows the approval queue entry points", ctx do
      character = draft_character_fixture(ctx.player, ctx.story)
      {:ok, _} = Characters.submit_for_approval(character)

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      assert has_element?(lv, "#master-approval-count", "1 awaiting approval")
      assert has_element?(lv, "#master-npcs")
      assert has_element?(lv, "#master-moderation")
    end

    test "the dashboard approves, rejects, filters and sets states", ctx do
      pending = draft_character_fixture(ctx.player, ctx.story)
      {:ok, _} = Characters.submit_for_approval(pending)
      other = draft_character_fixture(user_fixture(), ctx.story)
      {:ok, _} = Characters.submit_for_approval(other)
      npc = npc_fixture(ctx.master, ctx.story)
      {:ok, away} = Characters.create_state(ctx.story, %{name: "Away", can_play: false})

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/characters")
      assert has_element?(lv, "#approval-queue-count", "2")
      assert has_element?(lv, "#queue-#{pending.id}")

      lv
      |> form("#review-form-#{pending.id}", review: %{notes: ""})
      |> render_submit(%{decision: "approve"})

      assert Characters.get_character!(pending.id).approval_status == "approved"
      refute has_element?(lv, "#queue-#{pending.id}")

      lv
      |> form("#review-form-#{other.id}", review: %{notes: "Rework the background"})
      |> render_submit(%{decision: "reject"})

      rejected = Characters.get_character!(other.id)
      assert rejected.approval_status == "rejected"
      assert rejected.review_notes == "Rework the background"

      lv |> form("#character-filters", filters: %{npc: "true"}) |> render_change()
      assert has_element?(lv, "#characters-#{npc.id}")
      refute has_element?(lv, "#characters-#{pending.id}")

      lv
      |> form("#character-filters", filters: %{npc: "", approval_status: "rejected"})
      |> render_change()

      assert has_element?(lv, "#characters-#{other.id}")
      refute has_element?(lv, "#characters-#{npc.id}")

      lv
      |> form("#state-form-#{other.id}", character_state: %{state_id: away.id})
      |> render_change()

      assert Characters.get_character!(other.id).state_id == away.id
    end

    test "masters create NPCs", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/npcs/new")

      {:ok, _lv, html} =
        lv
        |> form("#character-form",
          character: %{name: "Bartender", description: "Polishes glasses", master_notes: "Spy"}
        )
        |> render_submit()
        |> follow_redirect(conn_for(ctx.master))

      assert html =~ "Bartender"
      [npc] = Characters.list_npcs(ctx.story.id)
      assert npc.master_notes == "Spy"
      assert npc.approval_status == "approved"
    end

    test "moderation deletes chat messages and forum posts", ctx do
      character = character_fixture(ctx.player, ctx.story)
      message = message_fixture(ctx.player, location_fixture(ctx.story), character)
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))
      [post] = Forum.list_story_posts(ctx.story.id)

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/moderation")
      assert has_element?(lv, "#delete-message-#{message.id}")
      assert has_element?(lv, "#delete-forum-post-#{post.id}")

      lv |> element("#delete-message-#{message.id}") |> render_click()
      lv |> element("#delete-forum-post-#{post.id}") |> render_click()

      refute has_element?(lv, "#delete-message-#{message.id}")
      refute has_element?(lv, "#delete-forum-post-#{post.id}")
      assert Chat.list_story_messages(ctx.story.id) == []
      assert Forum.list_story_posts(ctx.story.id) == []
      assert topic
    end
  end

  describe "GM states configuration" do
    test "the GDR admin adds, edits and removes states", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/states")
      assert has_element?(lv, "#states")

      lv
      |> form("#state-form", state: %{name: "Torpor", can_play: "false", position: "2"})
      |> render_submit()

      state = Enum.find(Characters.list_states(ctx.story), &(&1.name == "Torpor"))
      refute state.can_play
      assert has_element?(lv, "#state-#{state.id}")

      lv |> element("#delete-state-#{state.id}") |> render_click()
      refute has_element?(lv, "#state-#{state.id}")
    end

    test "masters cannot configure states", ctx do
      assert {:error, {_kind, %{to: _}}} =
               live(conn_for(ctx.master), ~p"/g/#{ctx.story}/gm/states")
    end
  end
end
