defmodule TannhauserGateWeb.DiaryLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Characters, Diary, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    owner = user_fixture()

    %{story: story, gm: gm, master: master, owner: owner, other: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp with_diary(ctx) do
    story = enable_modules(ctx.story, [:diary])
    Map.merge(ctx, %{story: story, character: character_fixture(ctx.owner, story)})
  end

  defp entry!(ctx, visibility) do
    {:ok, entry} =
      Diary.create_entry(ctx.owner, ctx.character, %{
        "title" => "#{visibility} page",
        "body" => "Some **rain**",
        "visibility" => visibility
      })

    entry
  end

  describe "module disabled" do
    test "the diary page redirects and the sheet hides diary and gallery", ctx do
      character = character_fixture(ctx.owner, ctx.story)

      assert {:error, {:redirect, %{to: to}}} =
               live(conn_for(ctx.owner), ~p"/g/#{ctx.story}/characters/#{character}/diary")

      assert to == ~p"/g/#{ctx.story}"

      {:ok, lv, _} = live(conn_for(ctx.owner), ~p"/g/#{ctx.story}/characters/#{character}")
      refute has_element?(lv, "#character-diary")
      refute has_element?(lv, "#character-gallery")
    end
  end

  describe "diary page" do
    setup :with_diary

    test "visibility matrix: other players see public entries only", ctx do
      public = entry!(ctx, "public")
      masters = entry!(ctx, "masters")
      private = entry!(ctx, "private")
      path = ~p"/g/#{ctx.story}/characters/#{ctx.character}/diary"

      {:ok, lv, _} = live(conn_for(ctx.other), path)
      assert has_element?(lv, "#diary-entry-#{public.id}")
      refute has_element?(lv, "#diary-entry-#{masters.id}")
      refute has_element?(lv, "#diary-entry-#{private.id}")
      refute has_element?(lv, "#diary-new-entry")
      refute has_element?(lv, "#diary-entry-#{public.id}-delete")

      for user <- [ctx.owner, ctx.master] do
        {:ok, lv, _} = live(conn_for(user), path)

        for entry <- [public, masters, private],
            do: assert(has_element?(lv, "#diary-entry-#{entry.id}"))

        assert has_element?(lv, "#diary-entry-#{private.id}-visibility", "Private")
        assert has_element?(lv, "#diary-entry-#{public.id}-delete")
        assert has_element?(lv, "#diary-moderation-note")
      end

      # Masters moderate but don't write a player's diary.
      {:ok, lv, _} = live(conn_for(ctx.master), path)
      refute has_element?(lv, "#diary-new-entry")
    end

    test "the owner writes, edits and deletes entries; Markdown is sanitized", ctx do
      {:ok, lv, _} =
        live(conn_for(ctx.owner), ~p"/g/#{ctx.story}/characters/#{ctx.character}/diary")

      assert has_element?(lv, "#diary-empty")
      lv |> element("#diary-new-entry") |> render_click()

      lv
      |> form("#diary-form",
        entry: %{
          title: "First night",
          game_date_label: "Day one",
          visibility: "masters",
          body: "**Bold** move <script>alert(1)</script>"
        }
      )
      |> render_submit()

      assert [entry] = Diary.list_entries(ctx.character, ctx.owner)
      assert %{visibility: "masters", game_date_label: "Day one"} = entry
      assert has_element?(lv, "#diary-entry-#{entry.id}-body strong", "Bold")
      refute has_element?(lv, "#diary-entry-#{entry.id}-body script")

      lv |> element("#diary-entry-#{entry.id}-edit") |> render_click()
      lv |> form("#diary-form", entry: %{title: "Second thoughts"}) |> render_submit()
      assert has_element?(lv, "#diary-entry-#{entry.id}", "Second thoughts")

      lv |> element("#diary-entry-#{entry.id}-delete") |> render_click()
      refute has_element?(lv, "#diary-entry-#{entry.id}")
      assert Diary.list_entries(ctx.character, ctx.owner) == []
    end

    test "masters write the diary of an NPC", ctx do
      npc = npc_fixture(ctx.master, ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/characters/#{npc}/diary")

      lv |> element("#diary-new-entry") |> render_click()

      lv
      |> form("#diary-form",
        entry: %{title: "Informant notes", body: "Paid.", visibility: "public"}
      )
      |> render_submit()

      assert [%{title: "Informant notes"}] = Diary.list_entries(npc, ctx.other)
    end

    test "a character of another GDR is not found", ctx do
      {other, _} = gdr_fixture()
      foreign = character_fixture(user_fixture(), other)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn_for(ctx.owner), ~p"/g/#{ctx.story}/characters/#{foreign}/diary")

      assert to == ~p"/g/#{ctx.story}/characters"
    end
  end

  describe "character sheet" do
    setup :with_diary

    test "shows the latest visible entries and links to the diary", ctx do
      public = entry!(ctx, "public")
      private = entry!(ctx, "private")

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/characters/#{ctx.character}")
      assert has_element?(lv, "#character-diary-link")
      assert has_element?(lv, "#character-diary-entry-#{public.id}")
      refute has_element?(lv, "#character-diary-entry-#{private.id}")
    end

    test "renders description and background as sanitized Markdown", ctx do
      {:ok, character} =
        Characters.update_character(ctx.character, %{
          description: "A **tall** figure <script>alert(1)</script>",
          background: "# Origins\n\n- born in the *rain*"
        })

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/characters/#{character}")
      assert has_element?(lv, "#character-description strong", "tall")
      refute has_element?(lv, "#character-description script")
      assert has_element?(lv, "#character-background li em", "rain")
    end

    test "the owner uploads pictures to the gallery; others only look", ctx do
      path = ~p"/g/#{ctx.story}/characters/#{ctx.character}"
      {:ok, lv, _} = live(conn_for(ctx.owner), path)
      assert has_element?(lv, "#character-gallery-empty")

      picture =
        file_input(lv, "#gallery-form", :gallery, [
          %{name: "me.png", content: png_fixture(), type: "image/png"}
        ])

      render_upload(picture, "me.png")
      lv |> form("#gallery-form", gallery: %{caption: "On the docks"}) |> render_submit()

      assert [image] = Diary.list_images(ctx.character)
      assert image.caption == "On the docks"
      assert has_element?(lv, "#gallery-image-#{image.id}", "On the docks")

      {:ok, other_lv, _} = live(conn_for(ctx.other), path)
      assert has_element?(other_lv, "#gallery-image-#{image.id}")
      refute has_element?(other_lv, "#gallery-form")
      refute has_element?(other_lv, "#gallery-delete-#{image.id}")

      lv |> element("#gallery-delete-#{image.id}") |> render_click()
      assert Diary.list_images(ctx.character) == []
    end

    test "rejects non-image uploads", ctx do
      {:ok, lv, _} = live(conn_for(ctx.owner), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      svg =
        file_input(lv, "#gallery-form", :gallery, [
          %{name: "evil.svg", content: "<svg></svg>", type: "image/svg+xml"}
        ])

      assert {:error, [[_ref, :not_accepted]]} = render_upload(svg, "evil.svg")

      disguised =
        file_input(lv, "#gallery-form", :gallery, [
          %{name: "evil.png", content: "<svg></svg>", type: "image/png"}
        ])

      render_upload(disguised, "evil.png")
      lv |> form("#gallery-form") |> render_submit()

      assert Diary.list_images(ctx.character) == []
      assert has_element?(lv, "#flash-error", Diary.error_message(:invalid_image))
    end
  end

  describe "sheet template" do
    test "the GM sets it and it prefills the background of new characters", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm")
      assert has_element?(lv, "#sheet-template-settings")

      lv
      |> form("#general-form", story: %{sheet_template: "## Who are you?"})
      |> render_submit()

      assert Stories.get_story!(ctx.story.id).sheet_template == "## Who are you?"

      {:ok, lv, _} = live(conn_for(ctx.other), ~p"/g/#{ctx.story}/characters/new")
      assert has_element?(lv, "#character_background", "## Who are you?")
    end
  end
end
