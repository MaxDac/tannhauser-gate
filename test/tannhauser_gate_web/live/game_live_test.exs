defmodule TannhauserGateWeb.GameLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Chat, Stories}

  setup :register_and_log_in_user

  setup do
    %{story: story_fixture()}
  end

  describe "authentication" do
    test "game pages require login", %{story: story} do
      conn = build_conn()

      for path <- [
            "/gdrs",
            "/g/#{story.id}",
            "/g/#{story.id}/characters",
            "/g/#{story.id}/map",
            "/admin"
          ] do
        assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, path)
      end
    end
  end

  describe "GDR selection" do
    test "lists published GDRs and hides drafts of others", %{conn: conn, story: story} do
      {draft, _gm} = gdr_fixture(%{name: "Secret Draft", status: "draft"})

      {:ok, _lv, html} = live(conn, ~p"/gdrs")
      assert html =~ story.name
      refute html =~ draft.name
    end

    test "draft GDRs cannot be entered by other users", %{conn: conn} do
      {draft, _gm} = gdr_fixture(%{status: "draft"})
      assert {:error, {kind, %{to: "/gdrs"}}} = live(conn, ~p"/g/#{draft}")
      assert kind in [:redirect, :live_redirect]
    end
  end

  describe "drawer" do
    test "shows the GDR sections and hides admin for regular users", %{conn: conn, story: story} do
      {:ok, _lv, html} = live(conn, ~p"/g/#{story}")
      assert html =~ ~s(id="drawer")
      assert html =~ "Characters"
      assert html =~ "Bank"
      assert html =~ "Jobs"
      assert html =~ "Forum"
      refute html =~ ~s(href="/admin")
      refute html =~ "GM dashboard"
    end

    test "shows the admin section for admins", %{story: story} do
      conn = log_in_user(build_conn(), admin_fixture())
      {:ok, _lv, html} = live(conn, ~p"/gdrs")
      assert html =~ ~s(href="/admin")
      {:ok, _lv, html} = live(conn, ~p"/g/#{story}")
      assert html =~ "GM dashboard"
    end

    test "applies the GDR theme", %{conn: conn, story: story} do
      {:ok, _lv, html} = live(conn, ~p"/g/#{story}")
      assert html =~ ~s(data-theme="#{story.theme}")
    end
  end

  describe "characters" do
    test "lists the characters of the GDR only", %{conn: conn, story: story} do
      mine = character_fixture(nil, story)
      other = character_fixture(nil, story_fixture())

      {:ok, _lv, html} = live(conn, ~p"/g/#{story}/characters")
      assert html =~ mine.name
      refute html =~ other.name
    end

    test "creates a character with an avatar and sheet values", %{
      conn: conn,
      user: user,
      story: story
    } do
      strength = sheet_item_fixture(story, %{name: "Strength", min_value: 1, max_value: 5})
      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/characters/new")

      assert has_element?(lv, "#character-form input[type='file'].console-field")
      assert has_element?(lv, "#avatar-hint")
      assert has_element?(lv, "#trait-#{strength.id}")

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
                   description: "Trench coat, tired eyes.",
                   background: "Former Warden.",
                   traits: %{to_string(strength.id) => "4"}
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Character created"
      assert html =~ "notepad-spirals"
      assert html =~ "Former Warden."
      assert html =~ "Strength"

      [character] = Characters.list_user_characters(user)
      assert "/uploads/" <> file = character.avatar_path
      assert String.ends_with?(file, ".png")
      assert File.exists?(Path.join(TannhauserGate.Storage.uploads_dir(), file))
    end

    test "rejects sheet values outside the GM's limits", %{conn: conn, story: story} do
      strength = sheet_item_fixture(story, %{name: "Strength", min_value: 1, max_value: 5})
      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/characters/new")

      html =
        lv
        |> form("#character-form",
          character: %{name: "Too strong", traits: %{to_string(strength.id) => "9"}}
        )
        |> render_submit()

      assert html =~ "Strength"
      assert html =~ "between"
      assert Characters.list_story_characters(story.id) == []
    end

    test "allows only one character per GDR", %{conn: conn, user: user, story: story} do
      existing = character_fixture(user, story)

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/g/#{story}/characters/new")

      assert path == "/g/#{story.id}/characters/#{existing.id}/edit"
    end

    test "validates the character form", %{conn: conn, story: story} do
      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/characters/new")

      assert lv
             |> form("#character-form", character: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert has_element?(
               lv,
               "#character_name[aria-invalid='true'][aria-describedby='character_name-errors']"
             )

      assert has_element?(lv, "#character_name-errors")
    end

    test "associates upload errors and clears them when the upload is cancelled", %{
      conn: conn,
      story: story
    } do
      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/characters/new")

      avatar =
        file_input(lv, "#character-form", :avatar, [
          %{name: "large.png", content: :binary.copy(<<0>>, 5_000_001), type: "image/png"}
        ])

      assert {:error, _} = render_upload(avatar, "large.png")

      assert has_element?(
               lv,
               "#character-form input[type='file'][aria-invalid='true'][aria-describedby='avatar-hint avatar-errors']"
             )

      assert has_element?(lv, "#avatar-errors")
      lv |> element("#character-form button[aria-label='Remove image']") |> render_click()
      refute has_element?(lv, "#avatar-errors")
      refute has_element?(lv, "#character-form input[type='file'][aria-invalid]")
    end

    test "shows the character sheet as a notepad", %{conn: conn, story: story} do
      character = character_fixture(nil, story)
      {:ok, _lv, html} = live(conn, ~p"/g/#{story}/characters/#{character}")

      assert html =~ "notepad"
      assert html =~ character.name
      assert html =~ character.description
      assert html =~ character.background
      refute html =~ "/characters/#{character.id}/edit"
    end

    test "does not show characters of another GDR", %{conn: conn, story: story} do
      foreign = character_fixture(nil, story_fixture())

      assert {:error, {:live_redirect, %{to: path, flash: %{"error" => _}}}} =
               live(conn, ~p"/g/#{story}/characters/#{foreign}")

      assert path == "/g/#{story.id}/characters"
    end

    test "forbids editing someone else's character", %{conn: conn, story: story} do
      character = character_fixture(nil, story)

      assert {:error, {:live_redirect, %{to: path, flash: %{"error" => _}}}} =
               live(conn, ~p"/g/#{story}/characters/#{character}/edit")

      assert path == "/g/#{story.id}/characters/#{character.id}"
    end

    test "edits and deletes own characters", %{conn: conn, user: user, story: story} do
      character = character_fixture(user, story)
      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/characters/#{character}/edit")

      assert {:ok, _lv, html} =
               lv
               |> form("#character-form", character: %{name: "Roy"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "Roy"

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/characters/#{character}")

      assert {:ok, _lv, html} =
               lv |> element("button", "Delete") |> render_click() |> follow_redirect(conn)

      assert html =~ "Character deleted"
      assert Characters.list_user_characters(user) == []
    end
  end

  describe "map and rooms" do
    setup %{user: user, story: story} do
      location = location_fixture(story, %{name: "Noodle Bar"})
      %{location: location, character: character_fixture(user, story)}
    end

    test "renders the map with clickable rooms", %{conn: conn, story: story, location: location} do
      {:ok, lv, html} = live(conn, ~p"/g/#{story}/map")
      assert html =~ ~s(id="city-map")
      assert html =~ ~s(data-location-name="Noodle Bar")

      assert {:error, {:live_redirect, %{to: path}}} =
               lv |> element("#room-area-#{location.id}") |> render_click()

      assert path == "/g/#{story.id}/rooms/#{location.id}"
    end

    test "sends messages showing avatar, name, time and text", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/g/#{ctx.story}/rooms/#{ctx.location}")

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

    test "rooms of another GDR are not reachable", %{conn: conn, story: story} do
      foreign = location_fixture(story_fixture())

      assert {:error, {:live_redirect, %{to: path}}} =
               live(conn, ~p"/g/#{story}/rooms/#{foreign}")

      assert path == "/g/#{story.id}/map"
    end

    test "receives messages from other players in real time", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/g/#{ctx.story}/rooms/#{ctx.location}")

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

    test "asks for a character when the user has none in the GDR", %{
      story: story,
      location: location
    } do
      conn = log_in_user(build_conn(), user_fixture())
      {:ok, _lv, html} = live(conn, ~p"/g/#{story}/rooms/#{location}")
      assert html =~ "You need a character in this GDR"
    end
  end

  describe "forum" do
    test "creates topics and posts", %{conn: conn, story: story} do
      section = section_fixture(story, %{name: "Lore"})

      {:ok, lv, html} = live(conn, ~p"/g/#{story}/forum")
      assert html =~ "Lore"

      {:ok, lv, _html} =
        lv
        |> element("a", "Lore")
        |> render_click()
        |> follow_redirect(conn, ~p"/g/#{story}/forum/sections/#{section}")

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

    test "each GDR has its own sections", %{conn: conn, story: story} do
      section_fixture(story, %{name: "Lore"})
      section_fixture(story_fixture(), %{name: "Foreign Affairs"})

      {:ok, _lv, html} = live(conn, ~p"/g/#{story}/forum")
      assert html =~ "Lore"
      refute html =~ "Foreign Affairs"
    end
  end

  describe "bank and jobs" do
    setup %{user: user, story: story} do
      %{character: character_fixture(user, story)}
    end

    test "takes a job and sends money", %{conn: conn, story: story, character: character} do
      job = job_fixture(story, %{name: "Courier", pay: 25})
      friend = character_fixture(nil, story, %{"name" => "Friend"})
      {:ok, _} = TannhauserGate.Bank.adjust(character, 100)

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/jobs")
      lv |> element("#take-job-#{job.id}") |> render_click()
      assert Characters.get_character!(character.id).job_id == job.id

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/bank")
      assert has_element?(lv, "#balance", "100")

      lv
      |> form("#transfer-form", transfer: %{to: friend.id, amount: "30"})
      |> render_submit()

      assert has_element?(lv, "#balance", "70")
      assert Characters.get_character!(friend.id).balance == 30
    end

    test "refuses transfers above the balance", %{conn: conn, story: story} do
      friend = character_fixture(nil, story)
      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/bank")

      html =
        lv
        |> form("#transfer-form", transfer: %{to: friend.id, amount: "30"})
        |> render_submit()

      assert html =~ "Not enough funds"
    end

    test "users without a character are asked to create one", %{story: story} do
      conn = log_in_user(build_conn(), user_fixture())

      assert {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/g/#{story}/bank")
      assert path == "/g/#{story.id}/characters/new"
    end
  end

  describe "GM dashboard" do
    test "is forbidden to regular users", %{conn: conn, story: story} do
      assert {:error, {_kind, %{to: path}}} = live(conn, ~p"/g/#{story}/gm")
      assert path == "/g/#{story.id}"
    end

    test "is forbidden to the GM of another GDR", %{story: story} do
      {_other, gm} = gdr_fixture()
      conn = log_in_user(build_conn(), gm)
      assert {:error, {_kind, %{to: _}}} = live(conn, ~p"/g/#{story}/gm")
    end

    test "lets the GM edit the GDR, theme, sheet, jobs and forum" do
      {story, gm} = gdr_fixture()
      conn = log_in_user(build_conn(), gm)

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/gm")

      lv
      |> form("#general-form", story: %{rules: "Be kind.", status: "published"})
      |> render_submit()

      assert Stories.get_story!(story.id).rules == "Be kind."

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/gm/theme")

      lv
      |> form("#theme-form",
        story: %{theme: "ember", theme_overrides: %{"primary" => "#112233", "accent" => "red;}"}}
      )
      |> render_submit()

      updated = Stories.get_story!(story.id)
      assert updated.theme == "ember"
      assert updated.theme_overrides == %{"primary" => "#112233"}

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/gm/sheet")

      lv
      |> form("#item-form", item: %{kind: "power", name: "Telepathy", min_value: 0, max_value: 3})
      |> render_submit()

      assert [%{name: "Telepathy", kind: "power"}] = TannhauserGate.Sheet.list_items(story)

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/gm/jobs")
      lv |> form("#job-form", job: %{name: "Smuggler", pay: 40}) |> render_submit()
      assert [%{name: "Smuggler", pay: 40}] = TannhauserGate.Bank.list_jobs(story)

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/gm/forum")
      lv |> form("#section-form", section: %{name: "Rumors"}) |> render_submit()

      assert Enum.any?(TannhauserGate.Forum.list_sections(story), fn {s, _} ->
               s.name == "Rumors"
             end)
    end

    test "lets the GM adjust balances" do
      {story, gm} = gdr_fixture()
      character = character_fixture(nil, story)
      conn = log_in_user(build_conn(), gm)

      {:ok, lv, _html} = live(conn, ~p"/g/#{story}/gm/balances")

      lv
      |> form("#adjust-form-#{character.id}", adjust: %{amount: "50", note: "Bonus"})
      |> render_submit()

      assert Characters.get_character!(character.id).balance == 50
    end
  end

  describe "GDR requests" do
    test "GMs can ask for a GDR" do
      gm = gm_fixture()
      conn = log_in_user(build_conn(), gm)
      {:ok, lv, _html} = live(conn, ~p"/gdrs/request")

      lv
      |> form("#gdr-request-form", gdr_request: %{name: "Dune RPG", pitch: "Spice."})
      |> render_submit()

      assert has_element?(lv, "#request-pending")
    end

    test "regular users are told they are not GMs", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/gdrs/request")
      assert has_element?(lv, "#not-gm")
    end
  end
end
