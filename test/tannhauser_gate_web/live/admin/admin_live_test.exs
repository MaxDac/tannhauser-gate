defmodule TannhauserGateWeb.AdminLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Accounts, Forum, Stories}

  @admin_paths [
    "/admin",
    "/admin/stories",
    "/admin/stories/new",
    "/admin/characters",
    "/admin/rooms",
    "/admin/users",
    "/admin/requests",
    "/admin/forum"
  ]

  describe "authorization" do
    test "regular users are redirected away from every admin page" do
      conn = log_in_user(build_conn(), user_fixture())

      for path <- @admin_paths do
        conn = get(conn, path)
        assert redirected_to(conn) == ~p"/gdrs"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Admins only."
      end
    end

    test "admins can open every admin page" do
      conn = log_in_user(build_conn(), admin_fixture())

      for path <- @admin_paths do
        assert {:ok, _lv, html} = live(conn, path)
        assert html =~ "admin-nav"
      end
    end
  end

  describe "as admin" do
    setup do
      admin = admin_fixture()
      %{admin: admin, conn: log_in_user(build_conn(), admin)}
    end

    test "creates a story and adds a room to its map", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/stories/new")

      assert has_element?(lv, "#story_map_svg.textarea.console-field.font-mono")

      {:ok, lv, html} =
        lv
        |> form("#story-form",
          story: %{
            name: "Off-world",
            world_background: "Colonies",
            map_width: 800,
            map_height: 600
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Story saved"
      story = Stories.get_story_by_name("Off-world")

      lv
      |> form("#location-form",
        location: %{name: "Colony bar", area: "10,10 90,10 90,90", color: "#86e0b0"}
      )
      |> render_submit()

      assert render(lv) =~ "Colony bar"
      assert [%{name: "Colony bar"}] = Stories.get_story!(story.id).locations
    end

    test "rejects unsafe map artwork", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/stories/new")

      html =
        lv
        |> form("#story-form", story: %{name: "Evil", map_svg: "<script>alert(1)</script>"})
        |> render_submit()

      assert html =~ "must not contain scripts"

      assert has_element?(
               lv,
               "#story_map_svg[aria-invalid='true'][aria-describedby='story_map_svg-errors']"
             )

      assert has_element?(lv, "#story_map_svg-errors")
      refute Stories.get_story_by_name("Evil")
    end

    test "reads and moderates room conversations", %{conn: conn} do
      user = user_fixture()
      story = story_fixture()
      location = location_fixture(story)
      character = character_fixture(user, story)
      message = message_fixture(user, location, character, "Tears in rain")

      {:ok, lv, html} = live(conn, ~p"/admin/rooms/#{location}")
      assert html =~ "Tears in rain"
      assert html =~ user.username

      lv |> element("#messages-#{message.id} button", "Delete") |> render_click()
      refute render(lv) =~ "Tears in rain"
    end

    test "can edit any character", %{conn: conn} do
      character = character_fixture()
      {:ok, lv, _html} = live(conn, ~p"/g/#{character.story_id}/characters/#{character}/edit")

      {:ok, _lv, html} =
        lv
        |> form("#character-form", character: %{name: "Leon"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Leon"
    end

    test "promotes users to admin and GM but not themselves to admin", %{
      conn: conn,
      admin: admin
    } do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/users")

      lv |> element("#toggle-admin-#{user.id}") |> render_click()
      assert Accounts.admin?(Accounts.get_user!(user.id))

      lv |> element("#toggle-gm-#{user.id}") |> render_click()
      assert Accounts.gm?(Accounts.get_user!(user.id))

      refute has_element?(lv, "#toggle-admin-#{admin.id}")
    end

    test "approves and rejects GDR requests", %{conn: conn} do
      gm = gm_fixture()
      {:ok, request} = TannhauserGate.GdrRequests.create_request(gm, %{name: "Dune RPG"})

      {:ok, lv, _html} = live(conn, ~p"/admin/requests")
      lv |> element("#approve-#{request.id}") |> render_click()

      assert %{owner_id: owner_id, status: "draft"} = Stories.get_story_by_name("Dune RPG")
      assert owner_id == gm.id
    end

    test "deletes forum sections of any GDR", %{conn: conn} do
      section = section_fixture(nil, %{name: "Announcements"})
      {:ok, lv, _html} = live(conn, ~p"/admin/forum")

      assert render(lv) =~ "Announcements"
      lv |> element("a[phx-value-id='#{section.id}']") |> render_click()
      refute render(lv) =~ "Announcements"
      refute Enum.any?(Forum.list_sections(), fn {s, _} -> s.id == section.id end)
    end
  end
end
