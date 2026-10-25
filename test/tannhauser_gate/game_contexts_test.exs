defmodule TannhauserGate.GameContextsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Accounts, Characters, Chat, Forum, Stories}
  alias TannhauserGate.Seeds.{ArkhamAdrift, DefaultGdr, NeonRepublic}
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
      assert again.banner_path == DefaultGdr.banner_path()
      # The seeded rooms plus the guild briefing room.
      assert length(again.locations) == length(TannhauserGate.Seeds.locations()) + 1
      assert length(again.locations) >= 8
      assert length(Forum.list_sections()) >= 3

      assert TannhauserGate.Stories.module_enabled?(again, :items)
      assert length(TannhauserGate.Items.list_items(again)) == 3

      assert [%{name: "Black market", location: %{name: "Neon Bazaar"}}] =
               TannhauserGate.Items.list_shops(again)

      assert TannhauserGate.Stories.module_enabled?(again, :guilds)

      assert [
               %{name: "Meridian Police Department", secret: false} = police,
               %{name: "Echo Underground", secret: true}
             ] =
               TannhauserGate.Guilds.list_guilds(again)

      assert Enum.any?(again.locations, &(&1.guild_id == police.id))

      assert TannhauserGate.Stories.module_enabled?(again, :chat_rp)
      assert TannhauserGate.Stories.module_enabled?(again, :auto_xp)
      assert %{chat_max_length: 2000, auto_xp_amount: 1, auto_xp_min_length: 300} = again

      assert TannhauserGate.Stories.module_enabled?(again, :esiti)
      assert TannhauserGate.Stories.module_enabled?(again, :quests)
      assert [%{status: "resolved"}] = TannhauserGate.Esiti.list_queue(again, "all")

      assert [%{visibility: "public", rewards_applied_at: %DateTime{}, participants: [_]}] =
               TannhauserGate.Quests.list_quests(again, admin)

      assert TannhauserGate.Stories.module_enabled?(again, :diary)
      assert TannhauserGate.Stories.module_enabled?(again, :boards)
      assert again.sheet_template =~ "## Origins"

      assert [%{title: "Welcome to Neo-Meridian", pinned: true}] =
               TannhauserGate.Boards.list_announcements(again)

      assert [%{name: "Undercity wall", zone: %{name: "Undercity"}} = board] =
               TannhauserGate.Boards.list_all_boards(again)

      assert %{} = notices = TannhauserGate.Boards.notices_by_board([board])
      assert [%{character: %{name: "Mara Quill"}}] = notices[board.id]

      assert TannhauserGate.Stories.module_enabled?(again, :calendar)
      assert TannhauserGate.Stories.module_enabled?(again, :weather)
      assert %{year: 2121, month_name: month} = TannhauserGate.Calendars.now(again)
      assert month in TannhauserGate.Calendars.get_calendar(again).month_names
      assert length(TannhauserGate.Weather.list_conditions(again)) == 5
      zones = TannhauserGate.Zones.list_zones(again)
      assert map_size(TannhauserGate.Weather.zone_weathers(again)) == length(zones)
    end

    test "run/0 seeds GM owners and flags every seeded account to change its password" do
      %{
        admin: admin,
        story: story,
        gm: gm,
        neon_republic: %{story: neon, gm: neon_gm},
        arkham_adrift: %{story: arkham, gm: arkham_gm}
      } = TannhauserGate.Seeds.run()

      gms = [gm, neon_gm, arkham_gm]
      assert Enum.all?([admin | gms], & &1.must_change_password)
      assert Enum.all?([admin | gms], & &1.confirmed_at)
      assert Enum.all?(gms, &Accounts.gm?/1)
      refute Accounts.admin?(gm)
      assert story.owner_id == gm.id
      assert neon.owner_id == neon_gm.id
      assert arkham.owner_id == arkham_gm.id
      assert Stories.role(gm, story) == :gdr_admin
      assert Stories.role(neon_gm, neon) == :gdr_admin
      assert Stories.role(arkham_gm, arkham) == :gdr_admin

      # A later run keeps a changed password and does not flag the account again.
      {:ok, _} = Accounts.set_must_change_password(gm, false)
      %{gm: gm_again} = TannhauserGate.Seeds.run()
      assert gm_again.id == gm.id
      refute gm_again.must_change_password

      assert [{"Platform admin", %{email: "admin@tannhauser.gate"}} | _] =
               TannhauserGate.Seeds.credentials()
    end

    test "run/0 seeds trackers, dice and periodic actions in the default story" do
      %{story: story} = TannhauserGate.Seeds.run()

      assert ["health", "stress"] =
               Enum.map(TannhauserGate.Trackers.list_trackers(story), & &1.slug)

      assert %{system: "pool", die_size: 10, special_tracker: "stress"} = story.dice_config

      assert [%{name: "Work the streets", zone_property: "danger"}] =
               TannhauserGate.PeriodicActions.list_actions(story)
    end

    test "run/0 seeds the Neon Republic GDR, idempotently" do
      %{story: default, neon_republic: %{story: neon}} = TannhauserGate.Seeds.run()
      %{story: default_again, neon_republic: %{story: again}} = TannhauserGate.Seeds.run()

      assert neon.id == again.id
      assert default.id == default_again.id
      assert default_again.is_default
      refute again.is_default
      assert %{name: "Neon Republic", theme: "azure", currency_name: "scrip"} = again
      assert again.map_svg == NeonRepublic.map_svg()
      assert again.banner_path == NeonRepublic.banner_path()
      assert "cyberpunk" in again.genres
      assert again.pitch =~ "Halcyon Bay"

      # The seeded rooms plus the guild ops floor, all in a zone.
      locations = Stories.list_locations(again)
      assert length(locations) == length(NeonRepublic.locations()) + 1
      zones = TannhauserGate.Zones.list_zones(again)
      assert length(zones) == 3

      assert Enum.all?(
               locations,
               &(&1.zone_id || &1.name == "Directorate Ops Floor")
             )

      assert length(TannhauserGate.Sheet.list_items(again)) ==
               length(NeonRepublic.sheet_items())

      assert [%{title: "The world", pages: [_, _, _, _]}] =
               TannhauserGate.Guide.list_sections(again)

      assert length(TannhauserGate.Bank.list_jobs(again)) == 6
      assert [%{options: [_, _, _, _]}] = TannhauserGate.Origins.list_groups(again)

      assert ["health", "edge", "static"] =
               Enum.map(TannhauserGate.Trackers.list_trackers(again), & &1.slug)

      assert %{system: "pool", die_size: 6, reroll_tracker: "edge"} = again.dice_config
      assert length(TannhauserGate.PeriodicActions.list_actions(again)) == 2

      assert length(TannhauserGate.Items.list_items(again)) == 4

      assert [%{name: "Auntie Ruo's barge", location: %{name: "The Drowned Market"}}] =
               TannhauserGate.Items.list_shops(again)

      assert [
               %{name: "Combine Security Directorate", secret: false},
               %{name: "The Loose Wires", secret: true}
             ] = TannhauserGate.Guilds.list_guilds(again)

      for key <-
            ~w(origins items guilds chat_rp auto_xp esiti quests diary boards calendar weather reports)a do
        assert Stories.module_enabled?(again, key), "#{key} should be enabled"
      end

      assert [%{status: "resolved"}] = TannhauserGate.Esiti.list_queue(again, "all")

      assert [%{title: "Welcome to the Neon Republic", pinned: true}] =
               TannhauserGate.Boards.list_announcements(again)

      assert %{year: 2093} = TannhauserGate.Calendars.now(again)
      assert length(TannhauserGate.Weather.list_conditions(again)) == 5
    end

    test "run/0 seeds the Arkham Adrift GDR, idempotently" do
      %{arkham_adrift: %{story: arkham}} = TannhauserGate.Seeds.run()
      %{arkham_adrift: %{story: again}} = TannhauserGate.Seeds.run()

      assert arkham.id == again.id
      refute again.is_default
      assert %{name: "Arkham Adrift", theme: "sepia", currency_name: "dollars"} = again
      assert again.banner_path == ArkhamAdrift.banner_path()
      assert again.map_svg == ArkhamAdrift.map_svg()
      assert "horror" in again.genres
      assert again.pitch =~ "Arkham"

      # The seeded rooms plus the guild vestry, all in a zone.
      locations = Stories.list_locations(again)
      assert length(locations) == length(ArkhamAdrift.locations()) + 1
      assert length(TannhauserGate.Zones.list_zones(again)) == 3

      assert Enum.all?(
               locations,
               &(&1.zone_id || &1.name == "Lamplighters' Vestry")
             )

      assert length(TannhauserGate.Sheet.list_items(again)) ==
               length(ArkhamAdrift.sheet_items())

      # The hope of the setting is part of the seeded guide.
      assert [%{title: "The world", pages: pages}] = TannhauserGate.Guide.list_sections(again)
      assert length(pages) == 5
      assert Enum.any?(pages, &(&1.title == "Hope and the Narrow Gate"))

      assert length(TannhauserGate.Bank.list_jobs(again)) == 6

      assert [
               %{name: "Archetype", options: [_, _, _, _, _, _]},
               %{name: "Creed", options: [_, _, _, _]}
             ] = TannhauserGate.Origins.list_groups(again)

      assert ["health", "dread", "grace"] =
               Enum.map(TannhauserGate.Trackers.list_trackers(again), & &1.slug)

      assert %{
               system: "pool",
               die_size: 10,
               special_tracker: "dread",
               reroll_tracker: "grace"
             } = again.dice_config

      assert length(TannhauserGate.PeriodicActions.list_actions(again)) == 4
      assert length(TannhauserGate.Items.list_items(again)) == 6

      assert [%{name: "Hester Crane's pawnshop", location: %{name: "Independence Square"}}] =
               TannhauserGate.Items.list_shops(again)

      assert [
               %{name: "The Lamplighters of St. Agnes", secret: false},
               %{name: "The Black Star Lodge", secret: true}
             ] = TannhauserGate.Guilds.list_guilds(again)

      for key <-
            ~w(origins items guilds chat_rp auto_xp esiti quests diary boards calendar weather reports)a do
        assert Stories.module_enabled?(again, key), "#{key} should be enabled"
      end

      assert [%{status: "resolved"}] = TannhauserGate.Esiti.list_queue(again, "all")

      assert [%{title: "Welcome to Arkham Adrift", pinned: true}] =
               TannhauserGate.Boards.list_announcements(again)

      assert %{year: 1923} = TannhauserGate.Calendars.now(again)
      assert length(TannhauserGate.Weather.list_conditions(again)) == 5
    end

    test "run/0 completes a bare placeholder story without overwriting edits" do
      {:ok, placeholder} =
        TannhauserGate.Stories.create_story(%{name: "Tannhauser Gate", summary: "Custom"})

      %{story: story} = TannhauserGate.Seeds.run()

      assert story.id == placeholder.id
      assert story.summary == "Custom"
      assert [%{title: "The world", pages: [_ | _]}] = TannhauserGate.Guide.list_sections(story)
      assert [_ | _] = TannhauserGate.Zones.list_zones(story)
      assert story.map_svg == TannhauserGate.Seeds.map_svg()

      # Idempotent: a second run adds nothing.
      TannhauserGate.Seeds.run()
      assert [_] = TannhauserGate.Guide.list_sections(story)
      assert length(TannhauserGate.Zones.list_zones(story)) == 2
    end
  end
end
