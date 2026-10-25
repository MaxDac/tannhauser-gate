defmodule TannhauserGate.DirectoryTest do
  use TannhauserGate.DataCase, async: true

  import Ecto.Query

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Directory, Repo, Stories}
  alias TannhauserGate.Characters.Character

  @scores %{
    "graphics" => "4",
    "setting" => "5",
    "play_level" => "4",
    "technical" => "3",
    "features" => "4",
    "documentation" => "5",
    "management" => "3",
    "advice" => "More night events.",
    "conclusion" => "A great noir world, worth your time."
  }

  # An approved character created long enough ago to review its GDR.
  defp veteran(story, user \\ nil) do
    user = user || user_fixture()
    character = character_fixture(user, story)
    old = DateTime.add(DateTime.utc_now(:second), -30 * 86_400, :second)

    {1, _} =
      Repo.update_all(from(c in Character, where: c.id == ^character.id), set: [inserted_at: old])

    user
  end

  defp review!(story, scores \\ %{}) do
    user = veteran(story)
    {:ok, review} = Directory.save_review(user, story, Map.merge(@scores, scores))
    {user, review}
  end

  defp listing!(story, attrs) do
    {:ok, story} = Stories.update_story(story, attrs)
    story
  end

  describe "listing metadata" do
    test "validates genres, lifecycle, rating and pitch" do
      {story, _gm} = gdr_fixture()

      {:ok, story} =
        Stories.update_story_as_gm(story, %{
          "genres" => ["", "cyberpunk", "mystery_noir"],
          "lifecycle" => "beta",
          "content_rating" => "18",
          "pitch" => "Rain."
        })

      assert story.genres == ["cyberpunk", "mystery_noir"]
      assert {story.lifecycle, story.content_rating} == {"beta", "18"}

      {:error, changeset} =
        Stories.update_story_as_gm(story, %{
          "genres" => ["cyberpunk", "fantasy", "horror", "steampunk"],
          "lifecycle" => "gone",
          "content_rating" => "21",
          "pitch" => String.duplicate("x", 161)
        })

      assert %{genres: [_], lifecycle: [_], content_rating: [_], pitch: [_]} =
               errors_on(changeset)

      assert {:error, changeset} = Stories.update_story_as_gm(story, %{"genres" => ["elves"]})
      assert %{genres: [_]} = errors_on(changeset)
    end

    test "the banner is not castable from params" do
      {story, _gm} = gdr_fixture()
      {:ok, story} = Stories.update_story_as_gm(story, %{"banner_path" => "https://evil"})
      assert story.banner_path == nil
      {:ok, story} = Stories.set_banner(story, "/uploads/banner.png")
      assert story.banner_path == "/uploads/banner.png"
    end
  end

  describe "list_directory/3" do
    setup do
      user = user_fixture()
      {noir, _} = gdr_fixture(%{name: "Alpha Noir"})

      noir =
        listing!(noir, %{
          genres: ["cyberpunk", "mystery_noir"],
          lifecycle: "open",
          content_rating: "16",
          pitch: "Neon rain"
        })

      {elves, _} = gdr_fixture(%{name: "Beta Elves"})

      elves =
        listing!(elves, %{genres: ["fantasy"], lifecycle: "beta", content_rating: "12"})

      {draft, _} = gdr_fixture(%{name: "Gamma Draft", status: "draft"})
      %{user: user, noir: noir, elves: elves, draft: draft}
    end

    defp ids(entries), do: Enum.map(entries, & &1.id)

    test "filters by genre, lifecycle, rating and text", %{user: user, noir: noir, elves: elves} do
      assert ids(Directory.list_directory(user, %{"genre" => "cyberpunk"})) == [noir.id]
      assert ids(Directory.list_directory(user, %{"lifecycle" => "beta"})) == [elves.id]
      assert ids(Directory.list_directory(user, %{"rating" => "12"})) == [elves.id]
      assert ids(Directory.list_directory(user, %{"q" => "neon"})) == [noir.id]
      assert ids(Directory.list_directory(user, %{"q" => "elves"})) == [elves.id]
      assert ids(Directory.list_directory(user, %{"q" => "100%"})) == []
      # Unknown values are ignored.
      assert noir.id in ids(Directory.list_directory(user, %{"genre" => "nope"}))
    end

    test "hides others' drafts but shows them to admins and their GDR admin",
         %{user: user, draft: draft} do
      refute draft.id in ids(Directory.list_directory(user))
      assert draft.id in ids(Directory.list_directory(admin_fixture()))
      gm = Repo.get!(TannhauserGate.Accounts.User, draft.owner_id)
      assert draft.id in ids(Directory.list_directory(gm))
    end

    test "sorts by score, votes, activity, age and name",
         %{user: user, noir: noir, elves: elves} do
      review!(noir, %{"graphics" => "1", "setting" => "1"})
      review!(elves)
      {:ok, _} = Directory.vote(user, noir)
      character_fixture(user_fixture(), noir)
      character_fixture(user_fixture(), noir)
      npc_fixture(admin_fixture(), elves)

      [first, second | _] = Directory.list_directory(user, %{"sort" => "top"})
      assert {first.id, second.id} == {elves.id, noir.id}
      assert first.review_count == 1

      [first | _] = Directory.list_directory(user, %{"sort" => "votes"})
      assert first.id == noir.id
      assert first.votes == 1

      entries = Directory.list_directory(user, %{"sort" => "active"})
      assert hd(entries).id == noir.id
      # Reviewers' characters count as members, NPCs never do.
      assert hd(entries).members == 3
      assert Enum.find(entries, &(&1.id == elves.id)).members == 1

      online = fn id -> if id == elves.id, do: 5, else: 0 end
      [first | _] = Directory.list_directory(user, %{"sort" => "active"}, online: online)
      assert {first.id, first.online} == {elves.id, 5}

      assert ids(Directory.list_directory(user, %{"sort" => "name"})) |> Enum.take(2) ==
               [noir.id, elves.id]

      newest = Directory.list_directory(user, %{"sort" => "newest"})

      assert Enum.find_index(newest, &(&1.id == elves.id)) <
               Enum.find_index(newest, &(&1.id == noir.id))
    end
  end

  describe "reviews" do
    setup do
      {story, gm} = gdr_fixture()
      %{story: story, gm: gm}
    end

    test "require an approved, old enough, non-NPC character", %{story: story} do
      user = user_fixture()
      assert Directory.review_eligibility(user, story) == {:error, :no_character}

      character = draft_character_fixture(user, story)
      later = DateTime.add(DateTime.utc_now(), 15 * 86_400, :second)
      assert Directory.review_eligibility(user, story, later) == {:error, :no_character}

      {:ok, _} = character |> Ecto.Changeset.change(approval_status: "approved") |> Repo.update()
      # Too young with the default 14 days...
      assert Directory.review_eligibility(user, story) == {:error, :no_character}
      # ...but fine 15 days later.
      assert Directory.review_eligibility(user, story, later) == :ok

      assert {:error, :no_character} = Directory.save_review(user, story, @scores)
      assert {:ok, _} = Directory.save_review(user, story, @scores, later)
    end

    test "the GDR admin and masters cannot review", %{story: story, gm: gm} do
      veteran(story, gm)
      assert Directory.review_eligibility(gm, story) == {:error, :staff}

      master = user_fixture()
      {:ok, _} = Stories.add_master(story, master.username)
      veteran(story, master)
      assert Directory.review_eligibility(master, story) == {:error, :staff}
      assert {:error, :staff} = Directory.save_review(master, story, @scores)
    end

    test "drafts cannot be reviewed" do
      {draft, _} = gdr_fixture(%{status: "draft"})
      user = veteran(draft)
      assert Directory.review_eligibility(user, draft) == {:error, :not_published}
    end

    test "one review per user, editable by the author", %{story: story} do
      {user, review} = review!(story)
      assert review.advice == "More night events."

      {:ok, edited} =
        Directory.save_review(user, story, %{"conclusion" => "Changed my mind, still good."})

      assert edited.id == review.id
      assert length(Directory.list_reviews(story)) == 1

      assert {:error, changeset} = Directory.save_review(user, story, %{"graphics" => "6"})
      assert %{graphics: [_]} = errors_on(changeset)

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%TannhauserGate.Directory.Review{
          story_id: story.id,
          user_id: user.id,
          graphics: 1,
          setting: 1,
          play_level: 1,
          technical: 1,
          features: 1,
          documentation: 1,
          management: 1,
          conclusion: "Duplicate review"
        })
      end
    end

    test "validates scores and the conclusion", %{story: story} do
      user = veteran(story)

      {:error, changeset} =
        Directory.save_review(
          user,
          story,
          Map.merge(@scores, %{"setting" => "0", "conclusion" => ""})
        )

      assert %{setting: [_], conclusion: [_]} = errors_on(changeset)
    end

    test "only the GDR admin replies, to reviews of their GDR", %{story: story, gm: gm} do
      {author, review} = review!(story)
      {other_story, other_gm} = gdr_fixture()

      assert {:error, :unauthorized} =
               Directory.reply_to_review(author, story, review.id, %{"gm_reply" => "Hi"})

      assert {:error, :unauthorized} =
               Directory.reply_to_review(other_gm, story, review.id, %{"gm_reply" => "Hi"})

      # The other GDR admin cannot reach it through their own GDR either.
      assert {:error, :not_found} =
               Directory.reply_to_review(other_gm, other_story, review.id, %{"gm_reply" => "Hi"})

      master = user_fixture()
      {:ok, _} = Stories.add_master(story, master.username)

      assert {:error, :unauthorized} =
               Directory.reply_to_review(master, story, review.id, %{"gm_reply" => "Hi"})

      {:ok, replied} = Directory.reply_to_review(gm, story, review.id, %{"gm_reply" => "Thanks!"})
      assert replied.gm_reply == "Thanks!"
      assert replied.replied_at

      {:ok, edited} =
        Directory.reply_to_review(gm, story, review.id, %{"gm_reply" => "Thanks a lot!"})

      assert edited.gm_reply == "Thanks a lot!"

      # Platform-run GDRs are answered by platform admins.
      admin = admin_fixture()
      refute Directory.can_reply?(admin, story)
      platform = story_fixture()
      assert Directory.can_reply?(admin, platform)
    end

    test "hidden reviews leave the aggregates", %{story: story} do
      review!(story, %{"graphics" => "5"})

      {_, bad} =
        review!(story, Map.new(Directory.criteria(), fn {f, _, _} -> {to_string(f), "1"} end))

      aggregate = Directory.review_aggregate(story)
      assert aggregate.count == 2
      assert {:graphics, _, _, 3.0} = List.keyfind(aggregate.criteria, :graphics, 0)

      assert {:error, :unauthorized} = Directory.set_review_hidden(user_fixture(), bad.id, true)
      {:ok, hidden} = Directory.set_review_hidden(admin_fixture(), bad.id, true)
      assert hidden.hidden_at

      aggregate = Directory.review_aggregate(story)
      assert aggregate.count == 1
      assert {:graphics, _, _, 5.0} = List.keyfind(aggregate.criteria, :graphics, 0)
      assert_in_delta aggregate.overall, 4.142857, 0.0001
      assert [_] = Directory.list_reviews(story)
      assert [_, _] = Directory.list_reviews(story, include_hidden: true)

      [entry] = Directory.list_directory(user_fixture(), %{"q" => story.name})
      assert entry.review_count == 1

      {:ok, shown} = Directory.set_review_hidden(admin_fixture(), bad.id, false)
      refute shown.hidden_at
      assert Directory.review_aggregate(story).count == 2
    end
  end

  describe "votes" do
    setup do
      {story, _gm} = gdr_fixture()
      %{story: story, user: user_fixture()}
    end

    test "one vote per user per calendar month", %{story: story, user: user} do
      today = ~D[2026-10-25]
      assert {:ok, vote} = Directory.vote(user, story, today)
      assert vote.month == ~D[2026-10-01]
      assert Directory.voted?(user, story, ~D[2026-10-31])
      assert {:error, :already_voted} = Directory.vote(user, story, ~D[2026-10-31])

      refute Directory.voted?(user, story, ~D[2026-11-01])
      assert {:ok, _} = Directory.vote(user, story, ~D[2026-11-01])

      assert {:ok, _} = Directory.vote(user_fixture(), story, today)
      assert [%{votes: 2}] = Directory.list_directory(user, %{"q" => story.name}, today: today)
    end

    test "drafts cannot be voted, even by their staff" do
      {draft, gm} = gdr_fixture(%{status: "draft"})
      assert {:error, :not_found} = Directory.vote(user_fixture(), draft)
      assert {:error, :not_published} = Directory.vote(gm, draft)
    end

    test "ranking orders by votes, then score, per period", %{story: story} do
      today = ~D[2026-10-25]
      {second, _} = gdr_fixture(%{name: "Second"})
      {third, _} = gdr_fixture(%{name: "Third"})

      for _ <- 1..2, do: {:ok, _} = Directory.vote(user_fixture(), story, today)
      {:ok, _} = Directory.vote(user_fixture(), second, today)
      {:ok, _} = Directory.vote(user_fixture(), third, today)
      review!(third, %{"graphics" => "5"})
      review!(second, %{"graphics" => "1"})

      # Votes of older months only count in the yearly ranking.
      for _ <- 1..3, do: {:ok, _} = Directory.vote(user_fixture(), second, ~D[2026-03-10])
      {:ok, _} = Directory.vote(user_fixture(), third, ~D[2025-09-10])

      month = Directory.ranking(:month, today)

      assert Enum.map(month, &{&1.id, &1.votes, &1.rank}) ==
               [{story.id, 2, 1}, {third.id, 1, 2}, {second.id, 1, 3}]

      year = Directory.ranking(:year, today)

      assert Enum.map(year, &{&1.id, &1.votes}) ==
               [{second.id, 4}, {story.id, 2}, {third.id, 1}]

      # Unpublished GDRs leave the ranking.
      {:ok, _} = Stories.update_story(story, %{status: "draft"})
      refute story.id in Enum.map(Directory.ranking(:month, today), & &1.id)
    end
  end
end
