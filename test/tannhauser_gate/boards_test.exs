defmodule TannhauserGate.BoardsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Boards, Guilds, Stories, Zones}
  alias TannhauserGate.Boards.Announcement

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    story = enable_modules(story, [:boards])
    player = user_fixture()
    character = character_fixture(player, story)
    room = location_fixture(story, %{name: "Docks"})

    %{story: story, gm: gm, master: master, player: player, character: character, room: room}
  end

  defp announce!(ctx, attrs) do
    {:ok, announcement} =
      Boards.create_announcement(
        ctx.master,
        ctx.story,
        Enum.into(attrs, %{"title" => "News", "body" => "Hello"})
      )

    announcement
  end

  defp board!(ctx, attrs \\ %{}) do
    {:ok, board} =
      Boards.create_board(
        ctx.master,
        ctx.story,
        Enum.into(attrs, %{"name" => "Wall", "location_id" => ctx.room.id})
      )

    board
  end

  defp notice_attrs(ctx, attrs \\ %{}),
    do: Enum.into(attrs, %{"character_id" => to_string(ctx.character.id), "body" => "Hi"})

  describe "announcements" do
    test "only masters post; pinned first then newest; expired hidden", ctx do
      assert {:error, :unauthorized} =
               Boards.create_announcement(ctx.player, ctx.story, %{"title" => "x", "body" => "y"})

      old = announce!(ctx, %{"title" => "Old"})
      pinned = announce!(ctx, %{"title" => "Pinned", "pinned" => "true"})
      new = announce!(ctx, %{"title" => "New"})

      {:ok, expired} =
        %Announcement{story_id: ctx.story.id, title: "Gone", body: "x"}
        |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -60))
        |> Repo.insert()

      assert Enum.map(Boards.list_announcements(ctx.story), & &1.id) == [
               pinned.id,
               new.id,
               old.id
             ]

      assert expired.id in Enum.map(Boards.list_all_announcements(ctx.story), & &1.id)
    end

    test "unread count per user, cleared by marking them read", ctx do
      Boards.subscribe(ctx.story.id)
      assert Boards.unread_count(ctx.player, ctx.story) == 0

      announce!(ctx, %{})
      assert_receive {:boards, :announcement, _}
      announce!(ctx, %{"title" => "Second"})
      assert Boards.unread_count(ctx.player, ctx.story) == 2

      :ok = Boards.mark_announcements_read(ctx.player, ctx.story)
      player_id = ctx.player.id
      assert_receive {:boards, :read, %{user_id: ^player_id}}
      assert Boards.unread_count(ctx.player, ctx.story) == 0
      assert Boards.unread_count(ctx.master, ctx.story) == 2
    end

    test "announcements of another GDR are not found", ctx do
      {other, _} = gdr_fixture()
      announcement = announce!(ctx, %{})
      assert Boards.get_announcement(other, announcement.id) == nil
    end

    test "nothing is shown or posted when the module is disabled", ctx do
      announce!(ctx, %{})
      {:ok, story} = Stories.set_module_enabled(ctx.story, :boards, false)

      assert Boards.list_announcements(story) == []
      assert Boards.unread_count(ctx.player, story) == 0

      assert {:error, :module_disabled} =
               Boards.create_announcement(ctx.master, story, %{"title" => "x", "body" => "y"})
    end
  end

  describe "boards" do
    test "hang in exactly one room or zone of the same GDR", ctx do
      {:ok, zone} = Zones.create_zone(ctx.story, %{name: "Undercity"})

      assert {:error, changeset} =
               Boards.create_board(ctx.master, ctx.story, %{"name" => "Nowhere"})

      assert %{location_id: [_]} = errors_on(changeset)

      assert {:error, _} =
               Boards.create_board(ctx.master, ctx.story, %{
                 "name" => "Both",
                 "location_id" => ctx.room.id,
                 "zone_id" => zone.id
               })

      {other, _} = gdr_fixture()
      foreign_room = location_fixture(other)

      assert {:error, changeset} =
               Boards.create_board(ctx.master, ctx.story, %{
                 "name" => "Foreign",
                 "location_id" => foreign_room.id
               })

      assert %{location_id: ["is not a room of this GDR"]} = errors_on(changeset)

      assert {:error, :unauthorized} =
               Boards.create_board(ctx.player, ctx.story, %{
                 "name" => "Mine",
                 "location_id" => ctx.room.id
               })
    end

    test "a room shows its own boards and those of its zone", ctx do
      {:ok, zone} = Zones.create_zone(ctx.story, %{name: "Undercity"})
      {:ok, room} = Stories.update_location(ctx.room, %{zone_id: zone.id})
      elsewhere = location_fixture(ctx.story, %{name: "Tower"})

      room_board = board!(ctx, %{"name" => "Room board"})

      zone_board =
        board!(ctx, %{"name" => "Zone board", "location_id" => nil, "zone_id" => zone.id})

      assert Enum.map(Boards.boards_for_location(room, ctx.player), & &1.id) == [
               room_board.id,
               zone_board.id
             ]

      assert Boards.boards_for_location(elsewhere, ctx.player) == []
    end
  end

  describe "notices" do
    test "need a playable character of the user in the same GDR", ctx do
      board = board!(ctx)

      assert {:ok, notice} =
               Boards.post_notice(ctx.player, ctx.story, board, notice_attrs(ctx))

      assert notice.character_id == ctx.character.id

      outsider = user_fixture()

      assert {:error, :character_not_found} =
               Boards.post_notice(outsider, ctx.story, board, notice_attrs(ctx))

      {other, _} = gdr_fixture()
      other = enable_modules(other, [:boards])
      foreign = character_fixture(ctx.player, other)

      assert {:error, :character_not_found} =
               Boards.post_notice(
                 ctx.player,
                 ctx.story,
                 board,
                 notice_attrs(ctx, %{"character_id" => to_string(foreign.id)})
               )

      # A board of another GDR cannot be used through this one.
      assert {:error, :not_found} =
               Boards.post_notice(ctx.player, other, board, notice_attrs(ctx))

      assert Boards.get_board(other, board.id) == nil
    end

    test "masters post as playable NPCs", ctx do
      board = board!(ctx)
      npc = npc_fixture(ctx.master, ctx.story)

      assert {:ok, _} =
               Boards.post_notice(
                 ctx.master,
                 ctx.story,
                 board,
                 notice_attrs(ctx, %{"character_id" => to_string(npc.id)})
               )

      assert {:error, :character_not_found} =
               Boards.post_notice(
                 ctx.player,
                 ctx.story,
                 board,
                 notice_attrs(ctx, %{"character_id" => to_string(npc.id)})
               )
    end

    test "validate body length and a future expiry; expired ones are hidden", ctx do
      board = board!(ctx)

      assert {:error, changeset} =
               Boards.post_notice(
                 ctx.player,
                 ctx.story,
                 board,
                 notice_attrs(ctx, %{
                   "body" => String.duplicate("a", 1001),
                   "expires_at" => "2000-01-01T10:00"
                 })
               )

      assert %{body: [_], expires_at: [_]} = errors_on(changeset)

      {:ok, notice} = Boards.post_notice(ctx.player, ctx.story, board, notice_attrs(ctx))
      assert %{} = by_board = Boards.notices_by_board([board])
      assert [%{id: id}] = by_board[board.id]
      assert id == notice.id

      notice
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1))
      |> Repo.update!()

      assert Boards.notices_by_board([board]) == %{}
    end

    test "authors remove their notices, masters any", ctx do
      board = board!(ctx)
      {:ok, notice} = Boards.post_notice(ctx.player, ctx.story, board, notice_attrs(ctx))
      {:ok, other_notice} = Boards.post_notice(ctx.player, ctx.story, board, notice_attrs(ctx))
      stranger = user_fixture()

      refute Boards.can_delete_notice?(stranger, ctx.story, notice)
      assert {:error, :unauthorized} = Boards.delete_notice(stranger, ctx.story, notice)
      assert {:ok, _} = Boards.delete_notice(ctx.player, ctx.story, notice)
      assert {:ok, _} = Boards.delete_notice(ctx.master, ctx.story, other_notice)
    end

    test "guild boards are reserved to members and masters", ctx do
      story = enable_modules(ctx.story, [:guilds])
      {:ok, guild} = Guilds.create_guild(story, %{name: "Police"})
      board = board!(%{ctx | story: story}, %{"guild_id" => guild.id})
      ctx = %{ctx | story: story}

      refute Boards.accessible?(ctx.player, story, board)
      assert Boards.list_boards(story, ctx.player) == []
      assert [_] = Boards.list_boards(story, ctx.master)

      assert {:error, :unauthorized} =
               Boards.post_notice(ctx.player, story, board, notice_attrs(ctx))

      {:ok, _} = Guilds.enrol(ctx.master, story, guild, ctx.character.id)

      assert Boards.accessible?(ctx.player, story, board)
      assert {:ok, _} = Boards.post_notice(ctx.player, story, board, notice_attrs(ctx))

      # With the guilds module off the restriction no longer applies.
      {:ok, story} = Stories.set_module_enabled(story, :guilds, false)
      assert Boards.accessible?(user_fixture(), story, board)
    end
  end
end
