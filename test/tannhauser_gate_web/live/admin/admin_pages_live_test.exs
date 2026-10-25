defmodule TannhauserGateWeb.AdminPagesLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Accounts, Chat, GdrRequests, Repo, Stories}
  alias TannhauserGate.Characters.Character

  setup do
    admin = admin_fixture()
    %{admin: admin, conn: log_in_user(build_conn(), admin)}
  end

  describe "stories index" do
    test "lists stories with the default badge and their actions", %{conn: conn} do
      default = story_fixture(%{is_default: true, summary: "The main one"})
      other = story_fixture()

      {:ok, lv, _html} = live(conn, ~p"/admin/stories")

      assert has_element?(lv, "#stories td", default.name)
      assert has_element?(lv, "#stories td", other.name)
      assert has_element?(lv, "#stories span.badge", "default")
      assert has_element?(lv, "#stories span.line-clamp-2", "The main one")
      assert has_element?(lv, ~s(#stories a[href="/g/#{default.id}"]), "Open")
      assert has_element?(lv, ~s(#stories a[href="/admin/stories/#{default.id}/edit"]), "Edit")
    end

    test "deletes a story", %{conn: conn} do
      story = story_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/stories")

      lv
      |> element("#stories a[phx-click='delete'][phx-value-id='#{story.id}']")
      |> render_click()

      assert render(lv) =~ "Story deleted"
      refute has_element?(lv, "#stories td", story.name)
      refute Stories.get_story(story.id)
    end
  end

  describe "story form" do
    setup do
      story = story_fixture()
      %{story: story, location: location_fixture(story, %{name: "Old pier"})}
    end

    test "shows the map artwork and validates changes", %{conn: conn, story: story} do
      {:ok, lv, _html} = live(conn, ~p"/admin/stories/#{story}/edit")

      assert has_element?(lv, "#story-rooms svg image[href^='data:image/svg+xml;base64,']")

      lv |> form("#story-form", story: %{name: ""}) |> render_change()
      assert has_element?(lv, "#story_name-errors", "can't be blank")
    end

    test "updates an existing story", %{conn: conn, story: story} do
      {:ok, lv, _html} = live(conn, ~p"/admin/stories/#{story}/edit")

      {:ok, _lv, html} =
        lv
        |> form("#story-form", story: %{name: "Renamed city"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/stories/#{story}/edit")

      assert html =~ "Story saved"
      assert Stories.get_story!(story.id).name == "Renamed city"
    end

    test "keeps the form on invalid saves", %{conn: conn, story: story} do
      {:ok, lv, _html} = live(conn, ~p"/admin/stories/#{story}/edit")

      lv |> form("#story-form", story: %{name: "", map_width: 0}) |> render_submit()

      assert has_element?(lv, "#story_name-errors")
      assert has_element?(lv, "#story_map_width-errors")
      assert Stories.get_story!(story.id).name == story.name
    end

    test "edits, cancels and deletes rooms", %{conn: conn, story: story, location: location} do
      {:ok, lv, _html} = live(conn, ~p"/admin/stories/#{story}/edit")
      edit_link = "#locations a[phx-click='edit_location'][phx-value-id='#{location.id}']"
      cancel = "#location-form button[phx-click='new_location']"

      refute has_element?(lv, cancel)
      lv |> element(edit_link) |> render_click()
      assert has_element?(lv, "#story-rooms h3", "Edit room")
      assert has_element?(lv, "#location_name[value='Old pier']")

      lv |> element(cancel) |> render_click()
      assert has_element?(lv, "#story-rooms h3", "New room")
      refute has_element?(lv, cancel)

      lv |> element(edit_link) |> render_click()

      lv
      |> form("#location-form", location: %{name: "", area: ""})
      |> render_submit()

      assert has_element?(lv, "#location_name-errors")
      assert has_element?(lv, "#story-rooms h3", "Edit room")

      lv
      |> form("#location-form", location: %{name: "New pier", area: "1,1 50,1 50,50"})
      |> render_submit()

      assert render(lv) =~ "Room saved"
      assert has_element?(lv, "#locations td", "New pier")
      assert Stories.get_location!(location.id).name == "New pier"

      lv
      |> element("#locations a[phx-click='delete_location'][phx-value-id='#{location.id}']")
      |> render_click()

      assert render(lv) =~ "Room deleted"
      refute has_element?(lv, "#locations td", "New pier")
      assert Stories.get_story!(story.id).locations == []
    end
  end

  describe "characters" do
    test "lists every character and deletes one", %{conn: conn} do
      player = user_fixture()
      story = story_fixture()
      character = character_fixture(player, story)

      {:ok, lv, _html} = live(conn, ~p"/admin/characters")

      assert has_element?(lv, "#admin-characters td", character.name)
      assert has_element?(lv, "#admin-characters td", story.name)
      assert has_element?(lv, "#admin-characters td", player.username)

      assert has_element?(
               lv,
               ~s(#admin-characters a[href="/g/#{story.id}/characters/#{character.id}"]),
               "View"
             )

      assert has_element?(
               lv,
               ~s(#admin-characters a[href="/g/#{story.id}/characters/#{character.id}/edit"]),
               "Edit"
             )

      lv
      |> element("#admin-characters a[phx-click='delete'][phx-value-id='#{character.id}']")
      |> render_click()

      assert render(lv) =~ "Character deleted"
      refute has_element?(lv, "#admin-characters td", character.name)
      refute Repo.get(Character, character.id)
    end
  end

  describe "rooms" do
    setup do
      {story, gm} = gdr_fixture()
      location = location_fixture(story, %{name: "Neon bar"})
      %{story: story, gm: gm, location: location}
    end

    test "lists rooms with their story and message count", ctx do
      player = user_fixture()
      character = character_fixture(player, ctx.story)
      message_fixture(player, ctx.location, character, "One")
      message_fixture(player, ctx.location, character, "Two")

      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/rooms")

      assert has_element?(lv, "#admin-rooms td", "Neon bar")
      assert has_element?(lv, "#admin-rooms td", ctx.story.name)
      assert has_element?(lv, "#admin-rooms td", "2")

      {:ok, _lv, html} =
        lv
        |> element(~s(#admin-rooms a[href="/admin/rooms/#{ctx.location.id}"]), "Read")
        |> render_click()
        |> follow_redirect(ctx.conn, ~p"/admin/rooms/#{ctx.location}")

      assert html =~ "Two"
    end

    test "shows narration and new messages live", ctx do
      {:ok, narration} = Chat.narrate(ctx.gm, ctx.location, "The lights flicker")

      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/rooms/#{ctx.location}")

      assert has_element?(lv, "#messages-#{narration.id} .hero-book-open")
      assert has_element?(lv, "#messages-#{narration.id}", "The lights flicker")

      player = user_fixture()
      character = character_fixture(player, ctx.story)
      message = message_fixture(player, ctx.location, character, "Fresh arrival")

      assert has_element?(lv, "#messages-#{message.id}", "Fresh arrival")
      assert has_element?(lv, "#messages-#{message.id}", player.username)
    end
  end

  describe "GDR requests" do
    setup do
      gm = gm_fixture()
      {:ok, request} = GdrRequests.create_request(gm, %{name: "Dune RPG", pitch: "Spice"})
      %{gm: gm, request: request}
    end

    test "lists requests with their details", %{conn: conn, gm: gm, request: request} do
      {:ok, lv, _html} = live(conn, ~p"/admin/requests")

      assert has_element?(lv, "#admin-requests td", gm.username)
      assert has_element?(lv, "#admin-requests td", "Spice")
      assert has_element?(lv, "#admin-requests td", "pending")
      assert has_element?(lv, "#approve-#{request.id}")
      assert has_element?(lv, "#reject-#{request.id}")
    end

    test "approving refreshes the list", %{conn: conn, request: request} do
      {:ok, lv, _html} = live(conn, ~p"/admin/requests")

      lv |> element("#approve-#{request.id}") |> render_click()

      assert render(lv) =~ "Request approved. The GDR is now a draft."
      assert has_element?(lv, "#admin-requests td", "approved")
      refute has_element?(lv, "#approve-#{request.id}")
    end

    test "rejects a request", %{conn: conn, request: request} do
      {:ok, lv, _html} = live(conn, ~p"/admin/requests")

      lv |> element("#reject-#{request.id}") |> render_click()

      assert render(lv) =~ "Request rejected."
      assert has_element?(lv, "#admin-requests td", "rejected")
      refute has_element?(lv, "#reject-#{request.id}")
      assert GdrRequests.get_request!(request.id).status == "rejected"
      refute Stories.get_story_by_name("Dune RPG")
    end

    test "refuses to approve when the requester is no longer a GM", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/requests")
      {:ok, _} = Accounts.set_user_flags(ctx.gm, %{gm: false})

      lv |> element("#approve-#{ctx.request.id}") |> render_click()

      assert render(lv) =~ "The requester is no longer a game master."
      assert GdrRequests.get_request!(ctx.request.id).status == "pending"
      refute Stories.get_story_by_name("Dune RPG")
    end

    test "reports requests already reviewed by someone else", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/requests")
      {:ok, _} = GdrRequests.reject_request(ctx.request, admin_fixture())

      lv |> element("#approve-#{ctx.request.id}") |> render_click()

      assert render(lv) =~ "That request was already reviewed."
      refute has_element?(lv, "#approve-#{ctx.request.id}")
      assert has_element?(lv, "#admin-requests td", "rejected")
    end

    test "reports failures to reject a reviewed request", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/requests")
      {:ok, _} = GdrRequests.reject_request(ctx.request, admin_fixture())

      lv |> element("#reject-#{ctx.request.id}") |> render_click()

      assert render(lv) =~ "Could not reject the request."
    end

    test "reports approvals that can't create the GDR", ctx do
      story_fixture(%{name: "Dune RPG"})
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/requests")

      lv |> element("#approve-#{ctx.request.id}") |> render_click()

      assert render(lv) =~ "Could not approve the request."
      assert has_element?(lv, "#approve-#{ctx.request.id}")
      assert GdrRequests.get_request!(ctx.request.id).status == "pending"
    end
  end
end
