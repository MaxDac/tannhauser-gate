defmodule TannhauserGateWeb.BoardsLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Boards, Guilds, Stories, Zones}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp with_boards(ctx) do
    story = enable_modules(ctx.story, [:boards])
    room = location_fixture(story, %{name: "Docks"})

    Map.merge(ctx, %{
      story: story,
      room: room,
      character: character_fixture(ctx.player, story)
    })
  end

  defp announce!(ctx, attrs \\ %{}) do
    {:ok, announcement} =
      Boards.create_announcement(
        ctx.master,
        ctx.story,
        Enum.into(attrs, %{"title" => "Curfew tonight", "body" => "Stay **inside**."})
      )

    announcement
  end

  defp board!(ctx, attrs \\ %{}) do
    {:ok, board} =
      Boards.create_board(
        ctx.master,
        ctx.story,
        Enum.into(attrs, %{"name" => "Dock wall", "location_id" => ctx.room.id})
      )

    board
  end

  describe "module disabled" do
    test "pages redirect and links are hidden", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/master")
      refute has_element?(lv, "#nav-boards")
      refute has_element?(lv, "#master-boards")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      refute has_element?(lv, "#announcements")

      for path <- [~p"/g/#{ctx.story}/boards", ~p"/g/#{ctx.story}/master/boards"] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.gm), path)
        assert to == ~p"/g/#{ctx.story}"
      end
    end
  end

  describe "announcements" do
    setup :with_boards

    test "the unread badge appears live and clears on the home page", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters")
      refute has_element?(lv, "#nav-announcements-unread")

      announce!(ctx)
      assert has_element?(lv, "#nav-announcements-unread", "1")
      announce!(ctx, %{"title" => "Second"})
      assert has_element?(lv, "#nav-announcements-unread", "2")

      {:ok, home, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      refute has_element?(home, "#nav-announcements-unread")
      assert Boards.unread_count(ctx.player, ctx.story) == 0

      # The other open page hears the read too.
      refute has_element?(lv, "#nav-announcements-unread")
    end

    test "the home page lists announcements pinned first and updates live", ctx do
      old = announce!(ctx, %{"title" => "Old news"})
      pinned = announce!(ctx, %{"title" => "Rules", "pinned" => "true"})

      {:ok, home, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      assert has_element?(home, "#announcement-#{pinned.id}")
      assert has_element?(home, "#announcement-#{old.id}-body strong", "inside")
      refute has_element?(home, "#announcements-manage")

      ids =
        home
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#announcements [id^='announcement-'][id$='-body']")
        |> LazyHTML.attribute("id")

      assert ids == ["announcement-#{pinned.id}-body", "announcement-#{old.id}-body"]

      fresh = announce!(ctx, %{"title" => "Fresh", "body" => "<script>alert(1)</script>Hi"})
      assert has_element?(home, "#announcement-#{fresh.id}")
      refute has_element?(home, "#announcement-#{fresh.id}-body script")
    end

    test "masters manage announcements from the master page", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      assert has_element?(lv, "#master-boards")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/boards")

      lv
      |> form("#announcement-form",
        announcement: %{title: "Festival", body: "Lanterns", pinned: "true"}
      )
      |> render_submit()

      assert [%{title: "Festival", pinned: true} = a] = Boards.list_announcements(ctx.story)
      assert has_element?(lv, "#master-announcement-#{a.id}")

      lv |> element("#announcement-edit-#{a.id}") |> render_click()
      lv |> form("#announcement-form", announcement: %{title: "Festival!"}) |> render_submit()
      assert [%{title: "Festival!"}] = Boards.list_announcements(ctx.story)

      lv |> element("#announcement-delete-#{a.id}") |> render_click()
      assert Boards.list_all_announcements(ctx.story) == []
    end

    test "players cannot open the master page", ctx do
      assert {:error, {:redirect, _}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/boards")
    end
  end

  describe "notice boards" do
    setup :with_boards

    test "masters put up boards in a room or across a zone", ctx do
      {:ok, zone} = Zones.create_zone(ctx.story, %{name: "Undercity"})
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/boards")
      refute has_element?(lv, "#board_guild_id")

      lv
      |> form("#board-form", board: %{name: "Zone wall", zone_id: zone.id})
      |> render_submit()

      assert [%{name: "Zone wall"} = board] = Boards.list_all_boards(ctx.story)
      assert has_element?(lv, "#master-board-#{board.id}", "Undercity")

      lv |> element("#board-delete-#{board.id}") |> render_click()
      assert Boards.list_all_boards(ctx.story) == []
    end

    test "players pin notices as their character and remove their own", ctx do
      board = board!(ctx)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/boards")
      assert has_element?(lv, "#nav-boards")
      assert has_element?(lv, "#board-#{board.id}-empty")

      lv |> element("#board-#{board.id}-post") |> render_click()

      lv
      |> form("#notice-form-#{board.id}",
        notice: %{
          character_id: ctx.character.id,
          title: "Lost cat",
          body: "Answers to *Byte*"
        }
      )
      |> render_submit()

      assert %{} = notices = Boards.notices_by_board([board])
      assert [notice] = notices[board.id]
      assert notice.character_id == ctx.character.id
      assert has_element?(lv, "#notice-#{notice.id} em", "Byte")
      assert has_element?(lv, "#notice-#{notice.id}", ctx.character.name)

      # Another player sees it but cannot remove it; a master can.
      other = user_fixture()
      {:ok, other_lv, _} = live(conn_for(other), ~p"/g/#{ctx.story}/boards")
      assert has_element?(other_lv, "#notice-#{notice.id}")
      refute has_element?(other_lv, "#board-#{board.id}-post")
      refute has_element?(other_lv, "#notice-delete-#{notice.id}")

      lv |> element("#notice-delete-#{notice.id}") |> render_click()
      assert Boards.notices_by_board([board]) == %{}
      refute has_element?(other_lv, "#notice-#{notice.id}")
    end

    test "a notice cannot be signed by someone else's character", ctx do
      board = board!(ctx)
      stranger = character_fixture(user_fixture(), ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/boards")
      lv |> element("#board-#{board.id}-post") |> render_click()

      lv
      |> element("#notice-form-#{board.id}")
      |> render_submit(%{notice: %{character_id: stranger.id, body: "Fake"}})

      assert has_element?(lv, "#flash-error", Boards.error_message(:character_not_found))
      assert Boards.notices_by_board([board]) == %{}
    end

    test "rooms show their boards and the boards of their zone, live", ctx do
      {:ok, zone} = Zones.create_zone(ctx.story, %{name: "Undercity"})
      {:ok, room} = Stories.update_location(ctx.room, %{zone_id: zone.id})
      room_board = board!(ctx, %{"name" => "Room wall"})

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{room}")
      assert has_element?(lv, "#room-boards-panel")
      assert has_element?(lv, "#room-board-#{room_board.id}")

      zone_board =
        board!(ctx, %{"name" => "Zone wall", "location_id" => nil, "zone_id" => zone.id})

      assert has_element?(lv, "#room-board-#{zone_board.id}")

      {:ok, notice} =
        Boards.post_notice(ctx.player, ctx.story, zone_board, %{
          "character_id" => ctx.character.id,
          "body" => "Meet at dawn"
        })

      assert has_element?(lv, "#room-notice-#{notice.id}", "Meet at dawn")

      elsewhere = location_fixture(ctx.story, %{name: "Tower"})
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{elsewhere}")
      refute has_element?(lv, "#room-boards-panel")
    end

    test "guild boards are shown to members and masters only", ctx do
      story = enable_modules(ctx.story, [:guilds])
      ctx = %{ctx | story: story}
      {:ok, guild} = Guilds.create_guild(story, %{name: "Police"})
      board = board!(ctx, %{"guild_id" => guild.id})

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{story}/master/boards")
      assert has_element?(lv, "#board_guild_id")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{story}/boards")
      refute has_element?(lv, "#board-#{board.id}")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{story}/rooms/#{ctx.room}")
      refute has_element?(lv, "#room-board-#{board.id}")

      {:ok, _} = Guilds.enrol(ctx.master, story, guild, ctx.character.id)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{story}/boards")
      assert has_element?(lv, "#board-#{board.id}-guild", "Police")
      assert has_element?(lv, "#board-#{board.id}-post")
    end

    test "boards of another GDR cannot be used", ctx do
      {other, other_gm} = gdr_fixture()
      other = enable_modules(other, [:boards])
      foreign_room = location_fixture(other)

      {:ok, foreign} =
        Boards.create_board(other_gm, other, %{
          "name" => "Foreign",
          "location_id" => foreign_room.id
        })

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/boards")
      refute has_element?(lv, "#board-#{foreign.id}")
      render_hook(lv, "open_notice", %{"board" => to_string(foreign.id)})
      assert has_element?(lv, "#flash-error", Boards.error_message(:not_found))

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/boards")
      render_hook(lv, "delete_board", %{"id" => to_string(foreign.id)})
      assert [_] = Boards.list_all_boards(other)
    end
  end
end
