defmodule TannhauserGate.StoryRolesTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Accounts, Characters, Stories}

  describe "role/2" do
    test "ranks platform admins, the GDR admin, masters and players" do
      {story, gm} = gdr_fixture()
      user = user_fixture()
      {:ok, master} = Stories.add_master(story, user_fixture().username)

      assert Stories.role(admin_fixture(), story) == :platform_admin
      assert Stories.role(gm, story) == :gdr_admin
      assert Stories.role(master, story) == :master
      assert Stories.role(user, story) == :player
      assert Stories.role(nil, story) == :player
    end

    test "drafts are only accessible to the admins and masters" do
      {draft, gm} = gdr_fixture(%{status: "draft"})
      {:ok, master} = Stories.add_master(draft, user_fixture().username)
      user = user_fixture()

      assert Stories.role(user, draft) == nil
      assert Stories.role(nil, draft) == nil
      refute Stories.accessible?(user, draft)
      assert Stories.accessible?(master, draft)
      assert Stories.accessible?(gm, draft)
      assert Stories.accessible?(admin_fixture(), draft)
    end

    test "the owner loses the GDR admin role when the GM flag is revoked" do
      {story, gm} = gdr_fixture()
      {:ok, gm} = Accounts.set_user_flags(gm, %{gm: false})
      assert Stories.role(gm, story) == :player
    end

    test "predicates separate configuration from narration" do
      {story, gm} = gdr_fixture()
      {:ok, master} = Stories.add_master(story, user_fixture().username)
      admin = admin_fixture()
      player = user_fixture()

      assert Stories.gdr_admin?(admin, story)
      assert Stories.gdr_admin?(gm, story)
      refute Stories.gdr_admin?(master, story)
      refute Stories.gdr_admin?(player, story)

      assert Stories.master?(admin, story)
      assert Stories.master?(gm, story)
      assert Stories.master?(master, story)
      refute Stories.master?(player, story)

      {other, _} = gdr_fixture()
      refute Stories.master?(master, other)
    end
  end

  describe "masters" do
    test "adds and removes masters by username" do
      {story, gm} = gdr_fixture()
      user = user_fixture()

      assert {:ok, master} = Stories.add_master(story, " #{user.username} ")
      assert master.id == user.id
      assert [%{id: id}] = Stories.list_masters(story)
      assert id == user.id

      assert {:error, :already_master} = Stories.add_master(story, user.username)
      assert {:error, :owner} = Stories.add_master(story, gm.username)
      assert {:error, :user_not_found} = Stories.add_master(story, "nobody-here")

      assert :ok = Stories.remove_master(story, to_string(user.id))
      assert Stories.list_masters(story) == []
      assert {:error, :not_found} = Stories.remove_master(story, user.id)
    end

    test "masters see the drafts they narrate in the GDR list" do
      {draft, _gm} = gdr_fixture(%{status: "draft"})
      {:ok, master} = Stories.add_master(draft, user_fixture().username)

      assert draft.id in Enum.map(Stories.list_visible_stories(master), & &1.id)
      refute draft.id in Enum.map(Stories.list_visible_stories(user_fixture()), & &1.id)
    end

    test "masters can edit the characters of their GDR" do
      {story, _gm} = gdr_fixture()
      {:ok, master} = Stories.add_master(story, user_fixture().username)
      character = character_fixture(user_fixture(), story)

      assert Characters.can_edit?(master, character)
      refute Characters.can_edit?(user_fixture(), character)

      {other, _} = gdr_fixture()
      refute Characters.can_edit?(master, character_fixture(user_fixture(), other))
    end
  end
end
