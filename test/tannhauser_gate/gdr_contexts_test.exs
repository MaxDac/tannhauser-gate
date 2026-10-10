defmodule TannhauserGate.GdrContextsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Accounts, Bank, Characters, GdrRequests, Stories}
  alias TannhauserGate.Stories.Themes

  describe "GDR requests" do
    test "only game masters can ask, once, and admins approve" do
      assert {:error, :not_gm} = GdrRequests.create_request(user_fixture(), %{name: "Nope"})

      gm = gm_fixture()
      assert {:ok, request} = GdrRequests.create_request(gm, %{name: "Dune RPG", pitch: "Spice"})
      assert {:error, :pending} = GdrRequests.create_request(gm, %{name: "Again"})

      assert {:error, :unauthorized} = GdrRequests.approve_request(request, gm)
      assert {:ok, story} = GdrRequests.approve_request(request, admin_fixture())
      assert story.owner_id == gm.id
      assert story.status == "draft"
      assert Stories.get_owned_story(gm).id == story.id
      assert {:error, :already_has_gdr} = GdrRequests.create_request(gm, %{name: "Third"})
    end

    test "rejected requests can be retried" do
      gm = gm_fixture()
      {:ok, request} = GdrRequests.create_request(gm, %{name: "Dune RPG"})
      assert {:ok, _} = GdrRequests.reject_request(request, admin_fixture())
      assert {:ok, _} = GdrRequests.create_request(gm, %{name: "Dune RPG 2"})
    end

    test "a request can be reviewed only once, even with stale structs" do
      gm = gm_fixture()
      admin = admin_fixture()
      {:ok, request} = GdrRequests.create_request(gm, %{name: "Dune RPG"})

      assert {:ok, _} = GdrRequests.reject_request(request, admin)
      assert {:error, :not_pending} = GdrRequests.approve_request(request, admin)
      assert GdrRequests.get_request!(request.id).status == "rejected"
      assert Stories.get_owned_story(gm) == nil
    end

    test "approval fails if the requester is no longer a game master" do
      gm = gm_fixture()
      {:ok, request} = GdrRequests.create_request(gm, %{name: "Dune RPG"})
      {:ok, _} = Accounts.set_user_flags(gm, %{gm: false})

      assert {:error, :not_gm} = GdrRequests.approve_request(request, admin_fixture())
      assert GdrRequests.get_request!(request.id).status == "pending"
    end

    test "the database allows a single pending request per user" do
      gm = gm_fixture()
      {:ok, _} = GdrRequests.create_request(gm, %{name: "One"})

      assert {:error, changeset} =
               %GdrRequests.GdrRequest{user_id: gm.id, name: "Two"}
               |> Ecto.Changeset.change()
               |> Ecto.Changeset.unique_constraint(:user_id,
                 name: :gdr_requests_one_pending_per_user
               )
               |> Repo.insert()

      assert errors_on(changeset).user_id != []
    end
  end

  describe "map artwork" do
    test "is served as an inert SVG image" do
      story = story_fixture()
      assert Stories.map_artwork_src(%{story | map_svg: nil}) == nil

      "data:image/svg+xml;base64," <> encoded =
        Stories.map_artwork_src(%{story | map_svg: "<rect width=\"1\"/>"})

      assert Base.decode64!(encoded) =~ ~r/^<svg xmlns="http:\/\/www.w3.org\/2000\/svg".*<rect/
    end
  end

  describe "access" do
    test "drafts are only for their GM and admins" do
      {draft, gm} = gdr_fixture(%{status: "draft"})

      assert Stories.accessible?(gm, draft)
      assert Stories.accessible?(admin_fixture(), draft)
      refute Stories.accessible?(user_fixture(), draft)
      assert Stories.accessible?(user_fixture(), story_fixture())
    end

    test "a GM cannot own two GDRs" do
      {_story, gm} = gdr_fixture()
      other = story_fixture()

      assert {:error, changeset} =
               other
               |> Ecto.Changeset.change(owner_id: gm.id)
               |> Ecto.Changeset.unique_constraint(:owner_id)
               |> Repo.update()

      assert errors_on(changeset).owner_id != []
    end
  end

  describe "themes" do
    test "only valid hex colors are kept" do
      assert Themes.sanitize_overrides(%{
               "primary" => "#aabbcc",
               "accent" => "red",
               "evil" => "#000000",
               "secondary" => "#fff;}"
             }) ==
               %{"primary" => "#aabbcc"}

      assert Themes.style(%{"primary" => "#aabbcc"}) == "--color-primary:#aabbcc"
    end
  end

  describe "sheet" do
    test "values must stay within the GM's limits and are upserted" do
      story = story_fixture()
      item = sheet_item_fixture(story, %{min_value: 1, max_value: 5})
      user = user_fixture()

      attrs = %{"name" => "Pris", "story_id" => story.id}

      assert {:error, changeset} =
               Characters.create_character(user, Map.put(attrs, "traits", %{"#{item.id}" => "9"}))

      assert errors_on(changeset).traits != []

      assert {:ok, character} =
               Characters.create_character(user, Map.put(attrs, "traits", %{"#{item.id}" => "3"}))

      assert Characters.trait_values(character) == %{item.id => 3}

      assert {:ok, character} =
               Characters.update_character(character, %{"traits" => %{"#{item.id}" => "5"}})

      assert Characters.trait_values(character) == %{item.id => 5}
    end

    test "items validate min and max" do
      story = story_fixture()

      assert {:error, changeset} =
               TannhauserGate.Sheet.create_item(story, %{
                 kind: "skill",
                 name: "X",
                 min_value: 5,
                 max_value: 1
               })

      assert errors_on(changeset) != %{}
    end

    test "shrinking an item's range clamps existing values" do
      story = story_fixture()
      item = sheet_item_fixture(story, %{min_value: 0, max_value: 10})

      {:ok, character} =
        Characters.create_character(user_fixture(), %{
          "name" => "Pris",
          "story_id" => story.id,
          "traits" => %{"#{item.id}" => "9"}
        })

      assert {:ok, _} = TannhauserGate.Sheet.update_item(item, %{max_value: 5})
      assert Characters.trait_values(character) == %{item.id => 5}

      assert {:ok, _} = TannhauserGate.Sheet.update_item(item, %{min_value: 7, max_value: 8})
      assert Characters.trait_values(character) == %{item.id => 7}
    end

    test "a character can't be moved to another GDR" do
      story = story_fixture()
      character = character_fixture(nil, story)
      other = story_fixture()

      {:ok, updated} = Characters.update_character(character, %{"story_id" => other.id})
      assert updated.story_id == story.id
    end

    test "one character per user per GDR" do
      user = user_fixture()
      story = story_fixture()
      character_fixture(user, story)

      assert {:error, changeset} =
               Characters.create_character(user, %{"name" => "Second", "story_id" => story.id})

      assert "you already have a character in this GDR" in errors_on(changeset).story_id
    end
  end

  describe "bank" do
    setup do
      story = story_fixture()
      %{story: story, a: character_fixture(nil, story), b: character_fixture(nil, story)}
    end

    test "transfers move money and never overdraw", %{a: a, b: b} do
      {:ok, _} = Bank.adjust(a, 100)

      assert {:ok, _} = Bank.transfer(a, b.id, 40, "Rent")
      assert Characters.get_character!(a.id).balance == 60
      assert Characters.get_character!(b.id).balance == 40

      assert {:error, :insufficient_funds} = Bank.transfer(a, b.id, 1000)
      assert {:error, :invalid_amount} = Bank.transfer(a, b.id, -5)
      assert {:error, :same_character} = Bank.transfer(a, a.id, 5)
      assert {:error, :recipient_not_found} = Bank.transfer(a, -1, 5)
    end

    test "cannot send money to another GDR", %{a: a} do
      foreign = character_fixture(nil, story_fixture())
      {:ok, _} = Bank.adjust(a, 10)
      assert {:error, :recipient_not_found} = Bank.transfer(a, foreign.id, 5)
    end

    test "adjustments can't push balances below zero", %{a: a} do
      assert {:error, :insufficient_funds} = Bank.adjust(a, -5)
      assert {:ok, _} = Bank.adjust(a, 5)
      assert {:ok, _} = Bank.adjust(a, -5)
      assert Characters.get_character!(a.id).balance == 0
    end

    test "jobs belong to the GDR and pay once per interval", %{story: story, a: a} do
      job = job_fixture(story, %{pay: 25})
      assert {:error, :job_not_found} = Bank.set_job(a, job_fixture(story_fixture()).id)

      {:ok, a} = Bank.set_job(a, job.id)
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(25 * 3600, :second)

      assert Bank.pay_due(now) >= 1
      assert Characters.get_character!(a.id).balance == 25
      assert Bank.pay_due(now) == 0
      assert Characters.get_character!(a.id).balance == 25
      assert a.job_id == job.id
    end
  end

  test "accounts flags are set by admins only through set_user_flags" do
    user = user_fixture()
    assert {:ok, user} = Accounts.set_user_flags(user, %{gm: true})
    assert user.gm
    refute user.admin
  end
end
