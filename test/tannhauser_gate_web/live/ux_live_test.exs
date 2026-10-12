defmodule TannhauserGateWeb.UxLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.DataCase, only: [errors_on: 1]
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Chat, Stories}
  alias TannhauserGateWeb.GdrPresence

  setup do
    {story, gm} = gdr_fixture()
    player = user_fixture()

    %{
      story: story,
      gm: gm,
      player: player,
      character: character_fixture(player, story),
      location: location_fixture(story)
    }
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  describe "return to chat" do
    test "entering a room remembers it per user and GDR", ctx do
      assert Stories.last_location(ctx.player, ctx.story.id) == nil

      {:ok, _lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      assert Stories.last_location(ctx.player, ctx.story.id).id == ctx.location.id

      other = location_fixture(ctx.story)
      {:ok, _lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{other}")
      assert Stories.last_location(ctx.player, ctx.story.id).id == other.id

      {other_story, _} = gdr_fixture()
      assert Stories.last_location(ctx.player, other_story.id) == nil
      assert Stories.last_location(ctx.gm, ctx.story.id) == nil
    end

    test "the nav links back to the last room, except while in it", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      refute has_element?(lv, "#nav-return-to-chat")

      {:ok, room, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      refute has_element?(room, "#nav-return-to-chat")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters")

      assert has_element?(
               lv,
               "#nav-return-to-chat[href='/g/#{ctx.story.id}/rooms/#{ctx.location.id}']",
               ctx.location.name
             )

      assert has_element?(lv, "#header-return-to-chat")
    end
  end

  describe "character quick links" do
    test "the online list links to the sheet, the mailbox and the room", ctx do
      {:ok, _room, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}")

      id = "#online-user-#{ctx.player.id}-links"
      assert has_element?(lv, "#{id}-trigger", ctx.character.name)

      assert has_element?(
               lv,
               "#{id}-sheet[href='/g/#{ctx.story.id}/characters/#{ctx.character.id}']"
             )

      assert has_element?(
               lv,
               "#{id}-message[href='/g/#{ctx.story.id}/mail/new?to=#{ctx.character.id}']"
             )

      assert has_element?(
               lv,
               "#{id}-location[href='/g/#{ctx.story.id}/rooms/#{ctx.location.id}']"
             )
    end

    test "chat speakers and the character list get quick links", ctx do
      message = Chat.list_messages(ctx.location.id) |> List.first()
      assert message == nil

      {:ok, room, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")

      room
      |> form("#message-form-0",
        message: %{character_id: ctx.character.id, kind: "speech", body: "Like tears in rain"}
      )
      |> render_submit()

      [message] = Chat.list_messages(ctx.location.id)
      id = "#message-#{message.id}-speaker"
      assert has_element?(room, "#{id}-trigger.chat-name", ctx.character.name)

      assert has_element?(
               room,
               "#{id}-message[href='/g/#{ctx.story.id}/mail/new?to=#{ctx.character.id}']"
             )

      assert has_element?(room, "#{id}-location")

      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/characters")
      id = "#characters-#{ctx.character.id}-links"
      assert has_element?(lv, "#{id}-trigger", ctx.character.name)
      assert has_element?(lv, "#{id}-sheet")
      assert has_element?(lv, "#{id}-message")

      assert has_element?(
               lv,
               "#{id}-location[href='/g/#{ctx.story.id}/rooms/#{ctx.location.id}']"
             )
    end

    test "private rooms are only offered to the masters" do
      online = [
        %{character_id: 1, location_id: 7, location_name: "Den", location_private: true},
        %{character_id: 2, location_id: 8, location_name: "Bar", location_private: false},
        %{character_id: 3, location_id: nil, location_name: nil, location_private: false}
      ]

      assert GdrPresence.character_location(online, 1) == nil
      assert GdrPresence.character_location(online, 1, true) == %{id: 7, name: "Den"}
      assert GdrPresence.character_location(online, 2) == %{id: 8, name: "Bar"}
      assert GdrPresence.character_location(online, 3, true) == nil
      assert GdrPresence.character_location(online, 4, true) == nil
      assert GdrPresence.character_location(online, nil, true) == nil
    end
  end

  describe "community link" do
    test "the GDR admin sets it in GM config and the nav shows it", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      refute has_element?(lv, "#nav-community")

      {:ok, gm, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm")
      assert has_element?(gm, "#community-link-settings")

      html =
        gm
        |> form("#general-form", story: %{community_url: "discord.gg/nope"})
        |> render_submit()

      assert html =~ "must be an http(s) URL"

      gm
      |> form("#general-form",
        story: %{community_url: "https://discord.gg/tannhauser", community_label: "Discord"}
      )
      |> render_submit()

      assert has_element?(
               gm,
               "#nav-community[href='https://discord.gg/tannhauser'][target=_blank][rel='noopener noreferrer']",
               "Discord"
             )

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      assert has_element?(lv, "#nav-community", "Discord")
    end

    test "only http(s) URLs are accepted", ctx do
      for url <- ["javascript:alert(1)", "ftp://example.com", "https://", "https://bad host.com"] do
        assert {:error, changeset} = Stories.update_story_as_gm(ctx.story, %{community_url: url})
        assert %{community_url: [_]} = errors_on(changeset)
      end

      assert {:ok, story} =
               Stories.update_story_as_gm(ctx.story, %{community_url: "http://example.com/x"})

      assert {:ok, %{community_url: nil}} =
               Stories.update_story_as_gm(story, %{community_url: ""})
    end
  end
end
