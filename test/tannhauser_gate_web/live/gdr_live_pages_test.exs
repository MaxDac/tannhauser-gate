defmodule TannhauserGateWeb.GdrLivePagesTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Boards, GdrRequests, Repo, Stories}
  alias TannhauserGate.Boards.{Announcement, AnnouncementRead}

  defp conn_for(user), do: log_in_user(build_conn(), user)

  describe "My GDR page" do
    test "players who aren't game masters can't request a GDR" do
      {:ok, lv, _html} = live(conn_for(user_fixture()), ~p"/gdrs/request")

      assert has_element?(lv, "#not-gm")
      refute has_element?(lv, "#gdr-request-form")
      refute has_element?(lv, "#owned-gdr")
    end

    test "game masters running a GDR see it with a link to the dashboard" do
      {story, gm} = gdr_fixture()
      {:ok, lv, _html} = live(conn_for(gm), ~p"/gdrs/request")

      assert has_element?(lv, "#owned-gdr p", story.name)
      assert has_element?(lv, "#owned-gdr p", "Status: #{story.status}")
      assert has_element?(lv, ~s(#open-dashboard[href="/g/#{story.id}/gm"]))
      refute has_element?(lv, "#gdr-request-form")
      refute has_element?(lv, "#not-gm")
    end

    test "game masters validate and send a request" do
      gm = gm_fixture()
      {:ok, lv, _html} = live(conn_for(gm), ~p"/gdrs/request")

      lv |> form("#gdr-request-form", gdr_request: %{name: "X"}) |> render_change()
      assert has_element?(lv, "#gdr_request_name-errors", "should be at least 2 character(s)")

      lv
      |> form("#gdr-request-form", gdr_request: %{name: "Blade City", pitch: "Rain"})
      |> render_submit()

      assert render(lv) =~ "Request sent. An admin will review it."
      assert has_element?(lv, "#request-pending", "Blade City")
      refute has_element?(lv, "#gdr-request-form")
      assert %{name: "Blade City", status: "pending"} = GdrRequests.latest_request(gm)
    end

    test "invalid requests keep the form with errors" do
      gm = gm_fixture()
      {:ok, lv, _html} = live(conn_for(gm), ~p"/gdrs/request")

      lv |> form("#gdr-request-form", gdr_request: %{name: ""}) |> render_submit()

      assert has_element?(lv, "#gdr_request_name-errors", "can't be blank")
      refute has_element?(lv, "#request-pending")
      refute GdrRequests.latest_request(gm)
    end

    test "a pending request hides the form" do
      gm = gm_fixture()
      {:ok, _} = GdrRequests.create_request(gm, %{name: "Waiting room"})

      {:ok, lv, _html} = live(conn_for(gm), ~p"/gdrs/request")

      assert has_element?(lv, "#request-pending", "Waiting room")
      refute has_element?(lv, "#gdr-request-form")
    end

    test "after a rejection the game master can ask again" do
      gm = gm_fixture()
      {:ok, request} = GdrRequests.create_request(gm, %{name: "Too dark"})
      {:ok, _} = GdrRequests.reject_request(request, admin_fixture())

      {:ok, lv, _html} = live(conn_for(gm), ~p"/gdrs/request")

      assert has_element?(lv, "#request-rejected", "Too dark")
      assert has_element?(lv, "#gdr-request-form")
      refute has_element?(lv, "#request-pending")
    end

    test "reports a request filed meanwhile from another tab" do
      gm = gm_fixture()
      {:ok, lv, _html} = live(conn_for(gm), ~p"/gdrs/request")
      {:ok, _} = GdrRequests.create_request(gm, %{name: "Other tab"})

      lv |> form("#gdr-request-form", gdr_request: %{name: "This tab"}) |> render_submit()

      assert render(lv) =~ "You already have a pending request."
    end

    test "reports a GDR assigned meanwhile" do
      gm = gm_fixture()
      {:ok, lv, _html} = live(conn_for(gm), ~p"/gdrs/request")

      {:ok, story} = Stories.create_story(%{name: "Assigned GDR"})
      {:ok, _} = story |> Ecto.Changeset.change(owner_id: gm.id) |> Repo.update()

      lv |> form("#gdr-request-form", gdr_request: %{name: "Second GDR"}) |> render_submit()

      assert render(lv) =~ "You already run a GDR."
      refute GdrRequests.latest_request(gm)
    end

    test "refuses forged requests from players who aren't game masters" do
      user = user_fixture()
      {:ok, lv, _html} = live(conn_for(user), ~p"/gdrs/request")

      render_hook(lv, "save", %{"gdr_request" => %{"name" => "Sneaky"}})

      assert render(lv) =~ "Only game masters can request a GDR."
      refute GdrRequests.latest_request(user)
    end
  end

  describe "GDR home" do
    setup do
      {story, gm} = gdr_fixture()
      %{story: story, gm: gm, player: user_fixture()}
    end

    test "shows the sheet items of the GDR", ctx do
      attribute =
        sheet_item_fixture(ctx.story, %{
          name: "Grit",
          min_value: 1,
          max_value: 5,
          description: "How much you endure."
        })

      skill = sheet_item_fixture(ctx.story, %{kind: "skill", name: "Hacking"})

      {:ok, lv, _html} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")

      assert has_element?(lv, "#home-attribute h2", "Attributes")
      assert has_element?(lv, "#home-attribute li", attribute.name)
      assert has_element?(lv, "#home-attribute li span", "1–5")
      assert has_element?(lv, "#home-attribute li p", "How much you endure.")
      assert has_element?(lv, "#home-skill h2", "Skills")
      assert has_element?(lv, "#home-skill li", skill.name)
    end

    test "flags announcements published since the last visit", ctx do
      story = enable_modules(ctx.story, [:boards])
      old = announce!(ctx.gm, story, "Old news")
      backdate(Announcement, old.id, -2 * 3600)

      :ok = Boards.mark_announcements_read(ctx.player, story)
      backdate_reads(ctx.player, story, -3600)
      fresh = announce!(ctx.gm, story, "Fresh news")

      {:ok, lv, _html} = live(conn_for(ctx.player), ~p"/g/#{story}")

      assert has_element?(lv, "#announcement-#{fresh.id}-new")
      assert has_element?(lv, "#announcement-#{old.id}")
      refute has_element?(lv, "#announcement-#{old.id}-new")
      refute has_element?(lv, "#announcements-manage")
    end

    test "masters with the world permission get a manage link", ctx do
      story = enable_modules(ctx.story, [:boards])

      {:ok, lv, _html} = live(conn_for(ctx.gm), ~p"/g/#{story}")

      assert has_element?(lv, ~s(#announcements-manage[href="/g/#{story.id}/master/boards"]))
      assert has_element?(lv, "#announcements-empty")
    end
  end

  defp announce!(user, story, title) do
    {:ok, announcement} =
      Boards.create_announcement(user, story, %{"title" => title, "body" => "Read me."})

    announcement
  end

  defp backdate(schema, id, seconds) do
    at = DateTime.add(DateTime.utc_now(), seconds, :second)
    Repo.update_all(from(r in schema, where: r.id == ^id), set: [inserted_at: at])
  end

  defp backdate_reads(user, story, seconds) do
    at = DateTime.add(DateTime.utc_now(), seconds, :second)

    Repo.update_all(
      from(r in AnnouncementRead, where: r.user_id == ^user.id and r.story_id == ^story.id),
      set: [last_seen_at: at]
    )
  end
end
