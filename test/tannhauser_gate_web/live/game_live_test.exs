defmodule TannhauserGateWeb.GameLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Chat}

  setup :register_and_log_in_user

  describe "authentication" do
    test "game pages require login" do
      conn = build_conn()

      for path <- ["/characters", "/map", "/forum", "/admin"] do
        assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, path)
      end
    end
  end

  describe "drawer" do
    test "shows the sections and hides admin for regular users", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/characters")
      assert html =~ ~s(id="drawer")
      assert html =~ "Characters"
      assert html =~ "City Map"
      assert html =~ "Forum"
      refute html =~ ~s(href="/admin")
    end

    test "shows the admin section for admins" do
      conn = log_in_user(build_conn(), admin_fixture())
      {:ok, _lv, html} = live(conn, ~p"/characters")
      assert html =~ ~s(href="/admin")
    end
  end

  describe "characters" do
    test "lists only the user's characters", %{conn: conn, user: user} do
      mine = character_fixture(user)
      theirs = character_fixture()

      {:ok, _lv, html} = live(conn, ~p"/characters")
      assert html =~ mine.name
      refute html =~ theirs.name
    end

    test "creates a character with an avatar", %{conn: conn, user: user} do
      story = story_fixture(is_default: true)
      {:ok, lv, _html} = live(conn, ~p"/characters/new")

      avatar =
        file_input(lv, "#character-form", :avatar, [
          %{name: "deckard.png", content: png_fixture(), type: "image/png"}
        ])

      assert render_upload(avatar, "deckard.png") =~ "Remove"

      assert {:ok, _show, html} =
               lv
               |> form("#character-form",
                 character: %{
                   name: "Deckard",
                   story_id: story.id,
                   description: "Trench coat, tired eyes.",
                   background: "Former Warden."
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Character created"
      assert html =~ "notepad-spirals"
      assert html =~ "Former Warden."

      [character] = Characters.list_user_characters(user)
      assert "/uploads/" <> file = character.avatar_path
      assert String.ends_with?(file, ".png")
      assert File.exists?(Path.join(TannhauserGate.Storage.uploads_dir(), file))
    end

    test "validates the character form", %{conn: conn} do
      story_fixture()
      {:ok, lv, _html} = live(conn, ~p"/characters/new")

      assert lv
             |> form("#character-form", character: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"
    end

    test "shows the character sheet as a notepad", %{conn: conn} do
      character = character_fixture()
      {:ok, _lv, html} = live(conn, ~p"/characters/#{character}")

      assert html =~ "notepad"
      assert html =~ character.name
      assert html =~ character.description
      assert html =~ character.background
      refute html =~ "/characters/#{character.id}/edit"
    end

    test "forbids editing someone else's character", %{conn: conn} do
      character = character_fixture()

      assert {:error, {:live_redirect, %{to: path, flash: %{"error" => _}}}} =
               live(conn, ~p"/characters/#{character}/edit")

      assert path == "/characters/#{character.id}"
    end

    test "edits and deletes own characters", %{conn: conn, user: user} do
      character = character_fixture(user)
      {:ok, lv, _html} = live(conn, ~p"/characters/#{character}/edit")

      assert {:ok, _lv, html} =
               lv
               |> form("#character-form", character: %{name: "Roy"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Roy"

      {:ok, lv, _html} = live(conn, ~p"/characters/#{character}")

      assert {:ok, _lv, html} =
               lv |> element("button", "Delete") |> render_click() |> follow_redirect(conn)

      assert html =~ "Character deleted"
      assert Characters.list_user_characters(user) == []
    end
  end

  describe "map and rooms" do
    setup %{user: user} do
      story = story_fixture(is_default: true)
      location = location_fixture(story, %{name: "Noodle Bar"})
      %{story: story, location: location, character: character_fixture(user, story)}
    end

    test "renders the map with clickable rooms", %{conn: conn, location: location} do
      {:ok, lv, html} = live(conn, ~p"/map")
      assert html =~ ~s(id="city-map")
      assert html =~ ~s(data-location-name="Noodle Bar")

      assert {:error, {:live_redirect, %{to: path}}} =
               lv |> element("#room-area-#{location.id}") |> render_click()

      assert path == "/rooms/#{location.id}"
    end

    test "sends messages showing avatar, name, time and text", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/rooms/#{ctx.location}")

      lv
      |> form("#message-form-0",
        message: %{character_id: ctx.character.id, body: "More human than human"}
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "More human than human"
      assert html =~ ctx.character.name
      assert html =~ "Avatar of #{ctx.character.name}"
      [message] = Chat.list_messages(ctx.location.id)
      assert html =~ TannhauserGateWeb.GameComponents.format_time(message.inserted_at)
      assert has_element?(lv, "#message-form-1")
    end

    test "receives messages from other players in real time", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/rooms/#{ctx.location}")

      other = user_fixture()
      other_character = character_fixture(other, ctx.story, %{"name" => "Rachael"})

      message_fixture(
        other,
        ctx.location,
        other_character,
        "Is this testing whether I'm a replicant?"
      )

      assert render(lv) =~ "Is this testing whether"
      assert render(lv) =~ "Rachael"
    end

    test "asks for a character when the user has none in the story", %{location: location} do
      conn = log_in_user(build_conn(), user_fixture())
      {:ok, _lv, html} = live(conn, ~p"/rooms/#{location}")
      assert html =~ "You need a character in this story"
    end
  end

  describe "forum" do
    test "creates topics and posts", %{conn: conn} do
      section = section_fixture(%{name: "Lore"})

      {:ok, lv, html} = live(conn, ~p"/forum")
      assert html =~ "Lore"

      {:ok, lv, _html} =
        lv
        |> element("a", "Lore")
        |> render_click()
        |> follow_redirect(conn, ~p"/forum/sections/#{section}")

      assert {:ok, lv, html} =
               lv
               |> form("#topic-form", topic: %{title: "Unicorn dreams", body: "First!"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Unicorn dreams"
      assert html =~ "First!"

      lv |> form("#post-form-0", post: %{body: "Second!"}) |> render_submit()
      html = render(lv)
      assert html =~ "Second!"
      {first, _} = :binary.match(html, "First!")
      {second, _} = :binary.match(html, "Second!")
      assert first < second
    end
  end
end
