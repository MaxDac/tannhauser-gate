defmodule TannhauserGate.StoriesExtraTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{GdrRequests, Modules, Stories}
  alias TannhauserGate.Stories.{Story, Themes}

  describe "GdrRequests" do
    setup do
      gm = gm_fixture()
      {:ok, request} = GdrRequests.create_request(gm, %{name: "Dune RPG"})
      %{gm: gm, request: request, admin: admin_fixture()}
    end

    test "count_pending/0 counts only pending requests", %{request: request, admin: admin} do
      {:ok, _} = GdrRequests.create_request(gm_fixture(), %{name: "Other"})
      assert GdrRequests.count_pending() == 2

      {:ok, _} = GdrRequests.reject_request(request, admin)
      assert GdrRequests.count_pending() == 1
      assert [%{name: "Dune RPG"}] = GdrRequests.list_requests("rejected")
    end

    test "reviewed requests can't be approved or rejected again", %{
      request: request,
      admin: admin
    } do
      {:ok, rejected} = GdrRequests.reject_request(request, admin)
      assert rejected.status == "rejected"

      assert {:error, :not_pending} = GdrRequests.approve_request(rejected, admin)
      assert {:error, :not_pending} = GdrRequests.reject_request(rejected, admin)
    end

    test "a stale pending copy can't be rejected twice", %{request: request, admin: admin} do
      {:ok, _} = GdrRequests.reject_request(request, admin)

      assert {:error, :not_pending} = GdrRequests.reject_request(request, admin_fixture())
      assert GdrRequests.get_request!(request.id).reviewed_by_id == admin.id
    end

    test "only admins can reject", %{request: request, gm: gm} do
      assert {:error, :unauthorized} = GdrRequests.reject_request(request, gm)
      assert GdrRequests.get_request!(request.id).status == "pending"
    end
  end

  describe "Stories" do
    test "anonymous visitors only see published stories" do
      published = story_fixture(%{status: "published"})
      draft = story_fixture(%{status: "draft"})

      ids = nil |> Stories.visible_stories_query() |> Repo.all() |> Enum.map(& &1.id)

      assert published.id in ids
      refute draft.id in ids
    end

    test "role helpers handle missing users and stories" do
      story = story_fixture()

      refute Stories.get_owned_story(nil)
      refute Stories.gdr_admin?(nil, nil)
      refute Stories.master?(user_fixture(), nil)
      assert Stories.permissions(nil, story) == MapSet.new()
      refute Stories.module_enabled?(nil, :boards)
      assert Stories.remember_location(nil, nil) == :ok
      refute Stories.last_location(nil, story.id)
      assert Stories.presence_status(nil, story.id) == "available"
    end

    test "set_master_permission/4 rejects unknown permissions" do
      {story, _gm} = gdr_fixture()
      {:ok, master} = Stories.add_master(story, user_fixture().username)

      assert {:error, :not_found} =
               Stories.set_master_permission(story, master.id, :can_fly, true)
    end

    test "master_error_message/1 explains every error" do
      for reason <- [:user_not_found, :owner, :already_master, :not_found] do
        assert Stories.master_error_message(reason) =~ ~r/\w+/
      end

      assert Stories.master_error_message(:owner) =~ "GDR admin"
    end

    test "creates, lists and deletes stories and rooms" do
      assert {:error, %Ecto.Changeset{}} = Stories.create_story()

      story = story_fixture()
      assert {:error, %Ecto.Changeset{} = changeset} = Stories.create_location(story)
      assert %{name: _, area: _} = errors_on(changeset)

      location = location_fixture(story)
      assert {:ok, _} = Stories.delete_location(location)
      assert Stories.get_story!(story.id).locations == []

      assert {:ok, %Story{}} = Stories.delete_story(story)
      refute Stories.get_story(story.id)
    end

    test "get_default_story/0 is nil without stories" do
      Repo.delete_all(Story)
      assert Stories.get_default_story() == nil
    end
  end

  describe "Themes" do
    test "exposes the default themes and rejects bad values" do
      assert Themes.default() in Themes.presets()
      assert "sepia" in Themes.presets()
      assert Themes.platform() == "platform"
      refute Themes.hex?(nil)
      refute Themes.hex?(123)
      assert Themes.sanitize_overrides(nil) == %{}
      assert Themes.style("not a map") == ""
    end
  end

  describe "Modules" do
    test "handles unknown keys and malformed maps" do
      assert :boards in Modules.keys()
      assert length(Modules.keys()) == length(Modules.all())
      refute Modules.module?(42)
      assert Modules.sanitize(nil) == %{}
      refute Modules.enabled?(nil, :boards)
    end
  end
end
