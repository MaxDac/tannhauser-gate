defmodule TannhauserGateWeb.PortalLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Directory, Repo, Stories}
  alias TannhauserGate.Characters.Character

  @review %{
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

  defp veteran(story, user \\ nil) do
    user = user || user_fixture()
    character = character_fixture(user, story)
    old = DateTime.add(DateTime.utc_now(:second), -30 * 86_400, :second)

    {1, _} =
      Repo.update_all(from(c in Character, where: c.id == ^character.id), set: [inserted_at: old])

    user
  end

  setup do
    {story, gm} = gdr_fixture(%{name: "Neo Meridian"})

    {:ok, story} =
      Stories.update_story(story, %{
        genres: ["cyberpunk"],
        lifecycle: "beta",
        content_rating: "18",
        pitch: "Rain and neon"
      })

    {elves, _} = gdr_fixture(%{name: "Elven Woods"})
    {:ok, elves} = Stories.update_story(elves, %{genres: ["fantasy"], content_rating: "12"})

    %{story: story, gm: gm, elves: elves}
  end

  describe "directory" do
    test "lists cards with listing info and filters through the URL", %{
      conn: conn,
      story: story,
      elves: elves
    } do
      {draft, _} = gdr_fixture(%{status: "draft"})
      conn = log_in_user(conn, user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/gdrs")

      assert has_element?(lv, "#gdrs-#{story.id}")
      assert has_element?(lv, "#gdrs-#{elves.id}")
      refute has_element?(lv, "#gdrs-#{draft.id}")
      assert has_element?(lv, "#gdr-profile-link-#{story.id}[href='/gdrs/#{story.id}']")
      assert has_element?(lv, "#gdr-enter-#{story.id}[href='/g/#{story.id}']")
      assert has_element?(lv, "#gdrs-#{story.id}", "Rain and neon")
      assert has_element?(lv, "#gdrs-#{story.id}", "Beta test")
      assert has_element?(lv, "#gdrs-#{story.id}", "18+")

      lv
      |> form("#directory-filters", filters: %{genre: "fantasy"})
      |> render_change()

      assert_patch(lv, ~p"/gdrs?genre=fantasy")
      assert has_element?(lv, "#gdrs-#{elves.id}")
      refute has_element?(lv, "#gdrs-#{story.id}")
      assert has_element?(lv, "#reset-filters")

      {:ok, lv, _html} = live(conn, ~p"/gdrs?q=neon&sort=name")
      assert has_element?(lv, "#gdrs-#{story.id}")
      refute has_element?(lv, "#gdrs-#{elves.id}")

      {:ok, lv, _html} = live(conn, ~p"/gdrs?rating=16")
      assert has_element?(lv, "#no-gdrs")
    end
  end

  describe "profile" do
    test "shows the listing, scores and lets users vote once a month", %{
      conn: conn,
      story: story
    } do
      {:ok, _} = Directory.save_review(veteran(story), story, @review)
      conn = log_in_user(conn, user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/gdrs/#{story}")

      assert has_element?(lv, "#profile-pitch", "Rain and neon")
      assert has_element?(lv, "#aggregate-graphics", "4.0")
      assert has_element?(lv, "#reviews li", "A great noir world")
      assert has_element?(lv, "#enter-gdr[href='/g/#{story.id}']")
      assert has_element?(lv, "#review-eligibility")
      refute has_element?(lv, "#toggle-review-form")

      lv |> element("#vote-button") |> render_click()
      assert has_element?(lv, "#vote-button[disabled]")
      assert has_element?(lv, "#profile-votes", "1")
    end

    test "drafts are not visible to others nor votable by their staff" do
      {draft, gm} = gdr_fixture(%{status: "draft"})

      conn = log_in_user(build_conn(), user_fixture())
      assert {:error, {:live_redirect, %{to: "/gdrs"}}} = live(conn, ~p"/gdrs/#{draft}")
      assert {:error, {:live_redirect, %{to: "/gdrs"}}} = live(conn, ~p"/gdrs/nope")

      {:ok, lv, _html} = live(log_in_user(build_conn(), gm), ~p"/gdrs/#{draft}")
      refute has_element?(lv, "#vote-button")
    end

    test "eligible players write and edit their review", %{conn: conn, story: story} do
      user = veteran(story)
      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/gdrs/#{story}")

      lv |> element("#toggle-review-form") |> render_click()

      lv
      |> form("#review-form", review: Map.put(@review, "conclusion", "short"))
      |> render_submit()

      assert has_element?(lv, "#review-form")

      lv |> form("#review-form", review: @review) |> render_submit()
      refute has_element?(lv, "#review-form")
      assert has_element?(lv, "#reviews li", "A great noir world")
      assert has_element?(lv, "#toggle-review-form", "Edit your review")

      lv |> element("#toggle-review-form") |> render_click()

      lv
      |> form("#review-form", review: %{"conclusion" => "Even better after a month."})
      |> render_submit()

      assert has_element?(lv, "#reviews li", "Even better after a month.")
      assert [_] = Directory.list_reviews(story)
    end

    test "only the GDR admin replies", %{conn: conn, story: story, gm: gm} do
      {:ok, review} = Directory.save_review(veteran(story), story, @review)

      {:ok, lv, _html} = live(log_in_user(conn, user_fixture()), ~p"/gdrs/#{story}")
      refute has_element?(lv, "#review-reply-button-#{review.id}")
      render_click(lv, "save_reply", %{"review_id" => review.id, "reply" => %{"gm_reply" => "x"}})
      refute Directory.get_story_review(story, review.id).gm_reply

      {:ok, lv, _html} = live(log_in_user(build_conn(), gm), ~p"/gdrs/#{story}")
      lv |> element("#review-reply-button-#{review.id}") |> render_click()

      lv
      |> form("#review-reply-form-#{review.id}",
        reply: %{gm_reply: "Thanks, see you in the rain."}
      )
      |> render_submit()

      assert has_element?(lv, "#review-reply-#{review.id}", "Thanks, see you in the rain.")
      assert has_element?(lv, "#review-reply-button-#{review.id}", "Edit reply")
    end

    test "platform admins hide reviews from the scores", %{conn: conn, story: story} do
      {:ok, review} = Directory.save_review(veteran(story), story, @review)

      {:ok, lv, _html} = live(log_in_user(conn, user_fixture()), ~p"/gdrs/#{story}")
      refute has_element?(lv, "#review-toggle-hidden-#{review.id}")

      {:ok, lv, _html} = live(log_in_user(build_conn(), admin_fixture()), ~p"/gdrs/#{story}")
      lv |> element("#review-toggle-hidden-#{review.id}") |> render_click()
      assert has_element?(lv, "#review-hidden-#{review.id}")
      assert has_element?(lv, "#aggregate-overall", "–")

      {:ok, lv, _html} = live(log_in_user(build_conn(), user_fixture()), ~p"/gdrs/#{story}")
      refute has_element?(lv, "#reviews-#{review.id}")
      assert has_element?(lv, "#no-reviews")
    end
  end

  describe "admin reviews" do
    test "lists and toggles reviews", %{conn: conn, story: story} do
      {:ok, review} = Directory.save_review(veteran(story), story, @review)
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/reviews")

      assert has_element?(lv, "#reviews-#{review.id}", story.name)
      lv |> element("#admin-review-toggle-#{review.id}") |> render_click()
      assert has_element?(lv, "#admin-review-toggle-#{review.id}", "Unhide")
      assert Directory.get_story_review(story, review.id).hidden_at
    end
  end

  describe "ranking" do
    test "lists the most voted GDRs", %{conn: conn, story: story, elves: elves} do
      for _ <- 1..2, do: {:ok, _} = Directory.vote(user_fixture(), elves)
      {:ok, _} = Directory.vote(user_fixture(), story)

      {:ok, lv, _html} = live(log_in_user(conn, user_fixture()), ~p"/gdrs/ranking")
      assert has_element?(lv, "#ranking-month-#{elves.id}-votes", "2")
      assert has_element?(lv, "#ranking-year-#{story.id}-votes", "1")
      assert has_element?(lv, "#ranking-month li:first-child#ranking-month-#{elves.id}")
    end
  end

  describe "GM listing settings" do
    test "the GDR admin edits the listing and uploads a banner", %{
      conn: conn,
      story: story,
      gm: gm
    } do
      {:ok, lv, _html} = live(log_in_user(conn, gm), ~p"/g/#{story}/gm")
      assert has_element?(lv, "#directory-listing-settings")

      png = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> :binary.copy(<<0>>, 64)

      banner =
        file_input(lv, "#general-form", :banner, [
          %{name: "banner.png", content: png, type: "image/png"}
        ])

      render_upload(banner, "banner.png")

      lv
      |> form("#general-form",
        story: %{
          pitch: "New tagline",
          genres: ["", "horror", "mystery_noir"],
          lifecycle: "closed",
          content_rating: "all"
        }
      )
      |> render_submit()

      story = Stories.get_story!(story.id)
      assert story.pitch == "New tagline"
      assert story.genres == ["horror", "mystery_noir"]
      assert {story.lifecycle, story.content_rating} == {"closed", "all"}
      assert "/uploads/" <> _ = story.banner_path
      assert has_element?(lv, "#listing-banner-image")

      lv |> element("#remove-listing-banner") |> render_click()
      refute Stories.get_story!(story.id).banner_path
    end

    test "fake images are rejected as banners", %{conn: conn, story: story, gm: gm} do
      {:ok, lv, _html} = live(log_in_user(conn, gm), ~p"/g/#{story}/gm")

      banner =
        file_input(lv, "#general-form", :banner, [
          %{name: "banner.png", content: "<svg onload=alert(1)>", type: "image/png"}
        ])

      render_upload(banner, "banner.png")
      lv |> form("#general-form", story: %{pitch: "Sneaky"}) |> render_submit()

      story = Stories.get_story!(story.id)
      refute story.banner_path
      assert story.pitch == "Rain and neon"
    end
  end
end
