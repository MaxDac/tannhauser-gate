defmodule TannhauserGate.GameContextsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Accounts, Characters, Chat, Forum, Stories}
  alias TannhauserGate.Stories.Location

  describe "accounts roles" do
    test "users default to regular users and can be promoted" do
      user = user_fixture()
      refute user.admin
      refute user.gm
      refute Accounts.admin?(user)
      refute Accounts.gm?(user)

      assert {:ok, promoted} = Accounts.set_user_flags(user, %{admin: true, gm: true})
      assert Accounts.admin?(promoted)
      assert Accounts.gm?(promoted)
    end
  end

  describe "stories" do
    test "create_story/1 validates the name" do
      assert {:error, changeset} = Stories.create_story(%{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "create_story/1 rejects scripts in the map svg" do
      for svg <- [
            "<script>alert(1)</script>",
            ~s|<rect onclick="alert(1)"/>|,
            ~s|<a href="javascript:alert(1)"/>|,
            "<foreignObject></foreignObject>"
          ] do
        assert {:error, changeset} = Stories.create_story(%{name: "Bad #{svg}", map_svg: svg})
        assert errors_on(changeset).map_svg != []
      end
    end

    test "only one story is the default" do
      first = story_fixture(is_default: true)
      second = story_fixture(is_default: true)

      assert Stories.get_default_story().id == second.id
      refute Repo.reload!(first).is_default
    end

    test "locations validate their polygon and color" do
      story = story_fixture()

      assert {:error, changeset} =
               Stories.create_location(story, %{name: "Bad", area: "1,2 3,4", color: "red"})

      assert errors_on(changeset).area != []
      assert errors_on(changeset).color != []

      location = location_fixture(story, %{area: "0,0 100,0 100,50 0,50"})
      assert Location.centroid(location) == {50.0, 25.0}
      assert [%{id: id}] = Stories.get_story!(story.id).locations
      assert id == location.id
    end
  end

  describe "characters" do
    test "create_character/3 stores the avatar path only through the explicit argument" do
      user = user_fixture()
      story = story_fixture()

      assert {:ok, character} =
               Characters.create_character(
                 user,
                 %{"name" => "Pris", "story_id" => story.id, "avatar_path" => "/evil.png"},
                 "/uploads/ok.png"
               )

      assert character.avatar_path == "/uploads/ok.png"
      assert character.user_id == user.id
    end

    test "can_edit?/2 allows owners and admins only" do
      owner = user_fixture()
      character = character_fixture(owner)

      assert Characters.can_edit?(owner, character)
      assert Characters.can_edit?(admin_fixture(), character)
      refute Characters.can_edit?(user_fixture(), character)
    end

    test "list_user_characters/2 filters by user and story" do
      user = user_fixture()
      story = story_fixture()
      mine = character_fixture(user, story)
      _other_story = character_fixture(user)
      _other_user = character_fixture(nil, story)

      assert [%{id: id}] = Characters.list_user_characters(user, story.id)
      assert id == mine.id
      assert length(Characters.list_user_characters(user)) == 2
    end
  end

  describe "chat" do
    setup do
      user = user_fixture()
      story = story_fixture()

      %{
        user: user,
        story: story,
        location: location_fixture(story),
        character: character_fixture(user, story)
      }
    end

    test "create_message/3 stores and broadcasts the message", ctx do
      Chat.subscribe(ctx.location.id)

      assert {:ok, message} =
               Chat.create_message(ctx.user, ctx.location, %{
                 "character_id" => ctx.character.id,
                 "body" => "  Wake up. Time to die?  "
               })

      assert message.body == "Wake up. Time to die?"
      assert_receive {:new_message, %{id: id, character: %{name: _}}}
      assert id == message.id
      assert [%{id: ^id}] = Chat.list_messages(ctx.location.id)
      assert Chat.count_messages_by_location() == %{ctx.location.id => 1}
    end

    test "create_message/3 refuses other users' characters", ctx do
      assert {:error, :unauthorized} =
               Chat.create_message(user_fixture(), ctx.location, %{
                 "character_id" => ctx.character.id,
                 "body" => "Hi"
               })
    end

    test "create_message/3 refuses characters from another story", ctx do
      other = character_fixture(ctx.user)

      assert {:error, :wrong_story} =
               Chat.create_message(ctx.user, ctx.location, %{
                 "character_id" => other.id,
                 "body" => "Hi"
               })
    end

    test "create_message/3 validates the body", ctx do
      assert {:error, %Ecto.Changeset{}} =
               Chat.create_message(ctx.user, ctx.location, %{
                 "character_id" => ctx.character.id,
                 "body" => "   "
               })
    end

    test "list_messages/1 returns messages oldest first", ctx do
      first = message_fixture(ctx.user, ctx.location, ctx.character, "one")
      second = message_fixture(ctx.user, ctx.location, ctx.character, "two")
      assert Enum.map(Chat.list_messages(ctx.location.id), & &1.id) == [first.id, second.id]
    end
  end

  describe "forum" do
    test "create_topic/3 creates the topic with its first post" do
      user = user_fixture()
      section = section_fixture()

      assert {:ok, topic} =
               Forum.create_topic(user, section, %{"title" => "Origami", "body" => "Unicorns?"})

      assert [%{body: "Unicorns?"}] = Forum.list_posts(topic)
      assert [%{post_count: 1}] = Forum.list_topics(section)

      assert [{%{id: id}, 1}] =
               Enum.filter(Forum.list_sections(), fn {s, _} -> s.id == section.id end)

      assert id == section.id
    end

    test "create_topic/3 is atomic" do
      user = user_fixture()
      section = section_fixture()

      assert {:error, changeset} =
               Forum.create_topic(user, section, %{"title" => "Empty", "body" => ""})

      assert "can't be blank" in errors_on(changeset).body
      assert Forum.list_topics(section) == []
    end

    test "list_posts/1 orders posts by creation time" do
      user = user_fixture()
      topic = topic_fixture(user, section_fixture())
      {:ok, _} = Forum.create_post(user, topic, %{"body" => "second"})
      {:ok, _} = Forum.create_post(user, topic, %{"body" => "third"})

      assert Enum.map(Forum.list_posts(topic), & &1.body) == [
               "The opening post",
               "second",
               "third"
             ]
    end
  end

  describe "seeds" do
    test "run/0 is idempotent and creates the default story, admin and sections" do
      %{admin: admin, story: story} = TannhauserGate.Seeds.run()
      %{story: again} = TannhauserGate.Seeds.run()

      assert Accounts.admin?(admin)
      assert story.id == again.id
      assert story.name == "Tannhauser Gate"
      assert story.is_default
      assert length(again.locations) == length(TannhauserGate.Seeds.locations())
      assert length(again.locations) >= 8
      assert length(Forum.list_sections()) >= 3
    end

    test "run/0 completes a bare placeholder story without overwriting edits" do
      {:ok, placeholder} =
        TannhauserGate.Stories.create_story(%{name: "Tannhauser Gate", summary: "Custom"})

      %{story: story} = TannhauserGate.Seeds.run()

      assert story.id == placeholder.id
      assert story.summary == "Custom"
      assert story.world_background not in [nil, ""]
      assert story.map_svg == TannhauserGate.Seeds.map_svg()
    end
  end
end
