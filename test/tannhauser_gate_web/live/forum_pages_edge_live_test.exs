defmodule TannhauserGateWeb.ForumPagesEdgeLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Forum, Repo, Sanctions, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    player = user_fixture()
    other = user_fixture()

    %{
      story: story,
      gm: gm,
      master: master,
      player: player,
      other: other,
      character: character_fixture(player, story)
    }
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp topic_path(ctx, topic), do: ~p"/g/#{ctx.story}/forum/topics/#{topic.id}"
  defp section_path(ctx, section), do: ~p"/g/#{ctx.story}/forum/sections/#{section.id}"

  defp mute!(ctx, user) do
    story = enable_modules(ctx.story, [:reports])

    {:ok, _} =
      Sanctions.issue(ctx.master, story, %{
        "user_id" => user.id,
        "kind" => "mute",
        "reason" => "Rude",
        "duration" => "permanent"
      })

    story
  end

  defp unapprove!(character),
    do: character |> Ecto.Changeset.change(approval_status: "pending") |> Repo.update!()

  describe "topic page: replies" do
    test "on-game topics offer the character pick and reject an empty reply", ctx do
      section = section_fixture(ctx.story, %{on_game: true})
      topic = topic_fixture(ctx.player, section, %{"character_id" => ctx.character.id})

      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, topic))
      assert has_element?(lv, "#post-form-0 option[value='#{ctx.character.id}']")

      lv
      |> form("#post-form-0", post: %{body: "", character_id: ctx.character.id})
      |> render_submit()

      assert has_element?(lv, "#post-form-0")
      assert length(Forum.list_posts(topic)) == 1

      lv
      |> form("#post-form-0", post: %{body: "In character", character_id: ctx.character.id})
      |> render_submit()

      assert has_element?(lv, "#post-form-1")
      assert has_element?(lv, "#forum-posts", "In character")
    end

    test "a locked topic refuses a forged reply", ctx do
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))
      {:ok, _} = Forum.set_topic_flags(ctx.master, ctx.story, topic, %{"locked" => true})

      {:ok, lv, _} = live(conn_for(ctx.other), topic_path(ctx, topic))
      assert has_element?(lv, "#topic-locked")
      refute has_element?(lv, "#post-form-0")

      render_hook(lv, "create_post", %{"post" => %{"body" => "Too late"}})
      assert has_element?(lv, "#flash-error", "This topic is locked.")
      assert length(Forum.list_posts(topic)) == 1
    end

    test "muted users cannot reply, rename or edit", ctx do
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))
      [post] = Forum.list_posts(topic)
      mute!(ctx, ctx.player)

      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, topic))

      lv |> form("#post-form-0", post: %{body: "Shouting"}) |> render_submit()
      assert has_element?(lv, "#flash-error", "muted")

      lv |> element("#edit-topic") |> render_click()
      lv |> form("#topic-title-form", topic: %{title: "Louder"}) |> render_submit()
      assert Forum.get_topic!(topic.id).title == "A topic"

      lv |> element("#edit-post-#{post.id}") |> render_click()
      lv |> form("#edit-post-form-#{post.id}", edit: %{body: "Rewritten"}) |> render_submit()
      assert hd(Forum.list_posts(topic)).body == "The opening post"
      assert has_element?(lv, "#flash-error", "muted")
    end

    test "a player who lost access after the page opened cannot reply", ctx do
      section = section_fixture(ctx.story, %{visibility: "approved"})
      topic = topic_fixture(ctx.player, section)
      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, topic))

      unapprove!(ctx.character)

      lv |> form("#post-form-0", post: %{body: "Hello?"}) |> render_submit()
      assert has_element?(lv, "#flash-error", "You cannot write in this section.")
      assert length(Forum.list_posts(topic)) == 1
    end

    test "a player deletes their own reply", ctx do
      topic = topic_fixture(ctx.other, section_fixture(ctx.story))
      {:ok, post} = Forum.create_post(ctx.player, topic, %{"body" => "Oops"})

      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, topic))
      lv |> element("#delete-post-#{post.id}") |> render_click()

      refute has_element?(lv, "#forum-posts", "Oops")
      assert length(Forum.list_posts(topic)) == 1
    end
  end

  describe "topic page: editing posts" do
    setup ctx do
      topic = topic_fixture(ctx.player, section_fixture(ctx.story))
      [post] = Forum.list_posts(topic)
      %{topic: topic, post: post}
    end

    test "cancelling an edit restores the post", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, ctx.topic))
      lv |> element("#edit-post-#{ctx.post.id}") |> render_click()
      assert has_element?(lv, "#edit-post-form-#{ctx.post.id}")

      render_hook(lv, "cancel_edit", %{})
      refute has_element?(lv, "#edit-post-form-#{ctx.post.id}")
      assert has_element?(lv, "#forum-posts", "The opening post")
    end

    test "an empty body keeps the editor open", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, ctx.topic))
      lv |> element("#edit-post-#{ctx.post.id}") |> render_click()

      lv |> form("#edit-post-form-#{ctx.post.id}", edit: %{body: ""}) |> render_submit()

      assert has_element?(lv, "#edit-post-form-#{ctx.post.id}")
      assert hd(Forum.list_posts(ctx.topic)).body == "The opening post"
    end

    test "saving without an open editor or someone else's post is refused", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, ctx.topic))
      render_hook(lv, "save_post", %{"edit" => %{"body" => "Sneaky"}})
      assert has_element?(lv, "#flash-error", "You cannot edit that post.")

      {:ok, lv, _} = live(conn_for(ctx.other), topic_path(ctx, ctx.topic))
      render_hook(lv, "edit_post", %{"id" => ctx.post.id})
      assert has_element?(lv, "#flash-error", "You cannot edit that post.")

      render_hook(lv, "delete_post", %{"id" => ctx.post.id})
      assert has_element?(lv, "#flash-error", "You cannot delete that post.")
      assert length(Forum.list_posts(ctx.topic)) == 1
    end
  end

  describe "topic page: title and deletion" do
    setup ctx do
      section = section_fixture(ctx.story)
      %{section: section, topic: topic_fixture(ctx.player, section)}
    end

    test "the author renames the topic, an empty title is rejected", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, ctx.topic))

      lv |> element("#edit-topic") |> render_click()
      lv |> form("#topic-title-form", topic: %{title: ""}) |> render_submit()
      assert has_element?(lv, "#topic-title-form")
      assert Forum.get_topic!(ctx.topic.id).title == "A topic"

      render_hook(lv, "cancel_topic", %{})
      refute has_element?(lv, "#topic-title-form")

      lv |> element("#edit-topic") |> render_click()
      lv |> form("#topic-title-form", topic: %{title: "Renamed"}) |> render_submit()
      refute has_element?(lv, "#topic-title-form")
      assert page_title(lv) =~ "Renamed"
      assert Forum.get_topic!(ctx.topic.id).title == "Renamed"
    end

    test "strangers cannot rename, delete or flag the topic", ctx do
      {:ok, lv, _} = live(conn_for(ctx.other), topic_path(ctx, ctx.topic))
      refute has_element?(lv, "#edit-topic")
      refute has_element?(lv, "#delete-topic")

      render_hook(lv, "save_topic", %{"topic" => %{"title" => "Hijacked"}})
      assert has_element?(lv, "#flash-error", "You cannot edit this topic.")

      render_hook(lv, "delete_topic", %{})
      assert has_element?(lv, "#flash-error", "You cannot delete this topic.")

      render_hook(lv, "toggle_flag", %{"flag" => "locked"})
      assert has_element?(lv, "#flash-error", "Only the GDR masters can do that.")

      topic = Forum.get_topic!(ctx.topic.id)
      assert topic.title == "A topic"
      refute topic.locked
    end

    test "the author deletes the topic and lands on the section", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), topic_path(ctx, ctx.topic))
      lv |> element("#delete-topic") |> render_click()

      assert_redirect(lv, section_path(ctx, ctx.section))
      assert_raise Ecto.NoResultsError, fn -> Forum.get_topic!(ctx.topic.id) end
    end
  end

  describe "section page" do
    setup ctx do
      %{section: section_fixture(ctx.story)}
    end

    test "an empty topic is rejected and the form stays", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), section_path(ctx, ctx.section))

      lv |> form("#topic-form", topic: %{title: "", body: ""}) |> render_submit()
      assert has_element?(lv, "#topic-form")
      assert Forum.list_topics(ctx.section, ctx.player) == []
    end

    test "muted users cannot open topics", ctx do
      mute!(ctx, ctx.player)
      {:ok, lv, _} = live(conn_for(ctx.player), section_path(ctx, ctx.section))

      lv |> form("#topic-form", topic: %{title: "Hi", body: "There"}) |> render_submit()
      assert has_element?(lv, "#flash-error", "muted")
      assert Forum.list_topics(ctx.section, ctx.player) == []
    end

    test "a player who lost access after the page opened cannot open topics", ctx do
      {:ok, section} = Forum.update_section(ctx.section, %{visibility: "approved"})
      {:ok, lv, _} = live(conn_for(ctx.player), section_path(ctx, section))

      unapprove!(ctx.character)

      lv |> form("#topic-form", topic: %{title: "Hi", body: "There"}) |> render_submit()
      assert has_element?(lv, "#flash-error", "You cannot write in this section.")
      assert Forum.list_topics(section, ctx.master) == []
    end

    test "pinned and locked topics show their markers", ctx do
      topic = topic_fixture(ctx.player, ctx.section)

      {:ok, _} =
        Forum.set_topic_flags(ctx.master, ctx.story, topic, %{"pinned" => true, "locked" => true})

      {:ok, lv, _} = live(conn_for(ctx.player), section_path(ctx, ctx.section))
      assert has_element?(lv, "#forum-topic-#{topic.id} .hero-bookmark-solid")
      assert has_element?(lv, "#forum-topic-#{topic.id} .hero-lock-closed-solid")
    end
  end
end
