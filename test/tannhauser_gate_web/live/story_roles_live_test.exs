defmodule TannhauserGateWeb.StoryRolesLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Forum, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  describe "route access" do
    test "players reach neither the GM dashboard nor the master tools", %{story: story} do
      conn = conn_for(user_fixture())

      for path <- [~p"/g/#{story}/gm", ~p"/g/#{story}/gm/masters", ~p"/g/#{story}/master"] do
        assert {:error, {_kind, %{to: to}}} = live(conn, path)
        assert to == "/g/#{story.id}"
      end
    end

    test "masters reach the master tools but not the configuration", %{
      story: story,
      master: master
    } do
      conn = conn_for(master)

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/master")
      assert has_element?(lv, "#master-entry-points")
      assert has_element?(lv, "#master-forum")
      refute has_element?(lv, "#master-gm-dashboard-link")

      assert {:error, {_kind, %{to: to}}} = live(conn, ~p"/g/#{story}/gm")
      assert to == "/g/#{story.id}"
    end

    test "masters of another GDR are denied", %{story: story} do
      {other, _gm} = gdr_fixture()
      {:ok, other_master} = Stories.add_master(other, user_fixture().username)

      assert {:error, {_kind, %{to: _}}} = live(conn_for(other_master), ~p"/g/#{story}/master")
    end

    test "the GDR admin and platform admins reach both areas", %{story: story, gm: gm} do
      for user <- [gm, admin_fixture()] do
        conn = conn_for(user)
        {:ok, lv, _html} = live(conn, ~p"/g/#{story}/master")
        assert has_element?(lv, "#master-gm-dashboard-link")
        {:ok, lv, _html} = live(conn, ~p"/g/#{story}/gm")
        assert has_element?(lv, "#gm-master-tools-link")
      end
    end

    test "masters can enter drafts and see them in the GDR list" do
      {draft, _gm} = gdr_fixture(%{name: "Hidden Draft", status: "draft"})
      {:ok, master} = Stories.add_master(draft, user_fixture().username)
      conn = conn_for(master)

      {:ok, lv, _html} = live(conn, ~p"/gdrs")
      assert has_element?(lv, "#gdr-masters-#{draft.id}")
      assert {:ok, _lv, _html} = live(conn, ~p"/g/#{draft}")
    end
  end

  describe "navigation" do
    test "shows the links matching the role", %{story: story, gm: gm, master: master} do
      {:ok, lv, _html} = live(conn_for(user_fixture()), ~p"/g/#{story}")
      refute has_element?(lv, "#nav-master-tools")
      refute has_element?(lv, "#nav-gm-dashboard")

      {:ok, lv, _html} = live(conn_for(master), ~p"/g/#{story}")
      assert has_element?(lv, "#nav-master-tools")
      refute has_element?(lv, "#nav-gm-dashboard")

      {:ok, lv, _html} = live(conn_for(gm), ~p"/g/#{story}")
      assert has_element?(lv, "#nav-master-tools")
      assert has_element?(lv, "#nav-gm-dashboard")
    end
  end

  describe "masters management" do
    test "the GDR admin adds and removes masters", %{story: story, gm: gm, master: master} do
      {:ok, lv, _html} = live(conn_for(gm), ~p"/g/#{story}/gm/masters")
      assert has_element?(lv, "#masters-#{master.id}")

      newcomer = user_fixture()

      lv
      |> form("#master-form", master: %{username: newcomer.username})
      |> render_submit()

      assert has_element?(lv, "#masters-#{newcomer.id}")

      lv |> form("#master-form", master: %{username: "ghost-user"}) |> render_submit()
      assert render(lv) =~ "No user with that username."

      lv |> element("#remove-master-#{master.id}") |> render_click()
      refute has_element?(lv, "#masters-#{master.id}")
      assert Enum.map(Stories.list_masters(story), & &1.id) == [newcomer.id]
    end
  end

  describe "moderation" do
    test "masters delete forum posts, players cannot", %{story: story, master: master} do
      topic = topic_fixture(user_fixture(), section_fixture(story))
      [post] = Forum.list_posts(topic)

      {:ok, lv, _html} = live(conn_for(user_fixture()), ~p"/g/#{story}/forum/topics/#{topic}")
      refute has_element?(lv, "#delete-post-#{post.id}")

      {:ok, lv, _html} = live(conn_for(master), ~p"/g/#{story}/forum/topics/#{topic}")
      lv |> element("#delete-post-#{post.id}") |> render_click()
      assert Forum.list_posts(topic) == []
    end
  end
end
