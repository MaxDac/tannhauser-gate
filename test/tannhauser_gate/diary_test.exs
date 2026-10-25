defmodule TannhauserGate.DiaryTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Diary, Guide, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    story = enable_modules(story, [:diary])
    owner = user_fixture()
    character = character_fixture(owner, story)

    %{
      story: story,
      gm: gm,
      master: master,
      owner: owner,
      other: user_fixture(),
      character: character
    }
  end

  defp entry!(ctx, visibility, title \\ nil) do
    {:ok, entry} =
      Diary.create_entry(ctx.owner, ctx.character, %{
        "title" => title || "A #{visibility} page",
        "body" => "Rain again.",
        "visibility" => visibility
      })

    entry
  end

  defp titles(entries), do: entries |> Enum.map(& &1.title) |> Enum.sort()

  describe "entries" do
    test "visibility matrix: owner and masters read everything, others only public", ctx do
      entry!(ctx, "public")
      entry!(ctx, "masters")
      entry!(ctx, "private")

      all = ["A masters page", "A private page", "A public page"]
      assert titles(Diary.list_entries(ctx.character, ctx.owner)) == all
      assert titles(Diary.list_entries(ctx.character, ctx.master)) == all
      assert titles(Diary.list_entries(ctx.character, ctx.gm)) == all
      assert titles(Diary.list_entries(ctx.character, ctx.other)) == ["A public page"]
    end

    test "only the owner writes a player's diary; masters write NPC diaries", ctx do
      attrs = %{"title" => "Mine", "body" => "x", "visibility" => "public"}

      assert {:error, :unauthorized} = Diary.create_entry(ctx.other, ctx.character, attrs)
      assert {:error, :unauthorized} = Diary.create_entry(ctx.master, ctx.character, attrs)
      assert {:ok, _} = Diary.create_entry(ctx.owner, ctx.character, attrs)

      npc = npc_fixture(ctx.master, ctx.story)
      assert {:ok, _} = Diary.create_entry(ctx.master, npc, attrs)
      assert {:error, :unauthorized} = Diary.create_entry(ctx.owner, npc, attrs)
    end

    test "edits by the owner, deletions by the owner or any master", ctx do
      entry = entry!(ctx, "public")

      assert {:error, :unauthorized} =
               Diary.update_entry(ctx.other, ctx.character, entry, %{"title" => "Hacked"})

      assert {:ok, %{title: "Edited"}} =
               Diary.update_entry(ctx.owner, ctx.character, entry, %{"title" => "Edited"})

      assert {:error, :unauthorized} = Diary.delete_entry(ctx.other, ctx.character, entry)
      assert {:ok, _} = Diary.delete_entry(ctx.master, ctx.character, entry)
      assert Diary.list_entries(ctx.character, ctx.owner) == []
    end

    test "validates title, body and visibility", ctx do
      assert {:error, changeset} =
               Diary.create_entry(ctx.owner, ctx.character, %{"visibility" => "everyone"})

      assert %{title: [_], body: [_], visibility: [_]} = errors_on(changeset)
    end

    test "entries of a character in another GDR are not found", ctx do
      {other_story, _} = gdr_fixture()
      other_story = enable_modules(other_story, [:diary])
      foreign = character_fixture(user_fixture(), other_story)
      entry = entry!(ctx, "public")

      assert Diary.get_entry(foreign, entry.id) == nil

      assert {:error, :unauthorized} =
               Diary.delete_entry(ctx.master, foreign, entry)
    end

    test "nothing works when the module is disabled", ctx do
      entry = entry!(ctx, "public")
      {:ok, _} = Stories.set_module_enabled(ctx.story, :diary, false)
      character = TannhauserGate.Characters.get_character(ctx.character.id)

      assert Diary.list_entries(character, ctx.owner) == []

      assert {:error, :module_disabled} =
               Diary.create_entry(ctx.owner, character, %{"title" => "x", "body" => "y"})

      assert {:error, :module_disabled} = Diary.delete_entry(ctx.owner, character, entry)
    end
  end

  describe "gallery" do
    defp upload!(name, content) do
      dir = Path.join(["tmp", "test_uploads", "diary_sources"])
      File.mkdir_p!(dir)
      path = Path.join(dir, "#{System.unique_integer([:positive])}-#{name}")
      File.write!(path, content)
      on_exit(fn -> File.rm(path) end)
      path
    end

    test "accepts PNG, JPEG and WebP images checked from their content", ctx do
      png = upload!("a.png", png_fixture())
      jpeg = upload!("b.jpg", <<0xFF, 0xD8, 0xFF, 0xE0>> <> "jpeg")
      webp = upload!("c.webp", "RIFF" <> <<0, 0, 0, 0>> <> "WEBPVP8 ")

      assert {:ok, %{caption: "Me", path: "/uploads/" <> _}} =
               Diary.add_image(ctx.owner, ctx.character, png, %{"caption" => "Me"})

      assert {:ok, _} = Diary.add_image(ctx.owner, ctx.character, jpeg)
      assert {:ok, _} = Diary.add_image(ctx.master, ctx.character, webp)
      assert length(Diary.list_images(ctx.character)) == 3
    end

    test "rejects SVG, disguised and oversized files", ctx do
      svg = upload!("x.png", ~s(<svg xmlns="http://www.w3.org/2000/svg"><script>1</script></svg>))
      text = upload!("x.jpg", "just text")
      big = upload!("big.png", png_fixture() <> :binary.copy(<<0>>, Diary.max_image_size()))

      assert {:error, :invalid_image} = Diary.add_image(ctx.owner, ctx.character, svg)
      assert {:error, :invalid_image} = Diary.add_image(ctx.owner, ctx.character, text)
      assert {:error, :too_large} = Diary.add_image(ctx.owner, ctx.character, big)
      assert Diary.list_images(ctx.character) == []
    end

    test "is limited to max_images/0 pictures and managed by owner or masters", ctx do
      png = upload!("a.png", png_fixture())

      assert {:error, :unauthorized} = Diary.add_image(ctx.other, ctx.character, png)

      for _ <- 1..Diary.max_images(),
          do: assert({:ok, _} = Diary.add_image(ctx.owner, ctx.character, png))

      assert Diary.free_slots(ctx.character) == 0
      assert {:error, :gallery_full} = Diary.add_image(ctx.owner, ctx.character, png)

      [image | _] = Diary.list_images(ctx.character)
      assert {:error, :unauthorized} = Diary.delete_image(ctx.other, ctx.character, image.id)
      assert {:ok, _} = Diary.delete_image(ctx.master, ctx.character, image.id)
    end

    test "images of another character are not found", ctx do
      png = upload!("a.png", png_fixture())
      {:ok, image} = Diary.add_image(ctx.owner, ctx.character, png)
      mine = character_fixture(ctx.other, ctx.story)

      assert {:error, :not_found} = Diary.delete_image(ctx.other, mine, image.id)
    end
  end

  describe "markdown" do
    test "the guide renderer strips scripts and event handlers" do
      html =
        Guide.to_html(
          "**bold**\n\n<script>alert(1)</script>\n\n<img src=x onerror=\"alert(2)\">\n\n[x](javascript:alert(3))"
        )

      assert html =~ "<strong>bold</strong>"
      refute html =~ "<script"
      refute html =~ "onerror"
      refute html =~ "javascript:"
    end
  end
end
