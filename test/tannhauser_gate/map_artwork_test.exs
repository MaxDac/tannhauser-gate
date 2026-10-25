defmodule TannhauserGate.MapArtworkTest do
  use TannhauserGate.DataCase, async: true

  alias TannhauserGate.Repo
  alias TannhauserGate.Seeds.{ArkhamAdrift, DefaultGdr, MapArtwork, NeonRepublic, TorontoByNight}
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.{Location, Story}

  Code.require_file(
    "../../priv/repo/migrations/20261025203014_upgrade_builtin_gdr_maps.exs",
    __DIR__
  )

  alias TannhauserGate.Repo.Migrations.UpgradeBuiltinGdrMaps

  @games [
    {"tannhauser-gate", DefaultGdr},
    {"neon-republic", NeonRepublic},
    {"arkham-adrift", ArkhamAdrift},
    {"toronto-by-night", TorontoByNight}
  ]

  describe "built-in artwork" do
    test "every game ships a distinct, valid current map" do
      assert MapArtwork.current_version() == 2
      assert MapArtwork.slugs() == Enum.map(@games, &elem(&1, 0))

      for {slug, module} <- @games do
        svg = module.map_svg()
        assert svg == MapArtwork.read!(slug)
        assert svg == MapArtwork.read!(slug, 2)
        refute svg == MapArtwork.read!(slug, 1)
        refute svg =~ "\r"

        changeset = Story.changeset(%Story{}, %{name: "Check #{slug}", map_svg: svg})
        assert changeset.valid?, "#{slug} artwork must pass the story validation"
      end
    end

    test "rooms and their pins lie inside the 1000x700 map" do
      for {_slug, module} <- @games, room <- module.locations() do
        {x, y} = Location.centroid(%Location{area: room.area})
        assert x > 0 and x < 1000 and y > 0 and y < 700, room.name
      end
    end

    test "only known games have artwork" do
      assert_raise FunctionClauseError, fn -> MapArtwork.read!("unknown") end
    end
  end

  describe "upgrade migration" do
    defp story_with(map_svg, attrs \\ %{}) do
      {:ok, story} =
        Stories.create_story(
          Map.merge(
            %{name: "Story #{System.unique_integer([:positive])}", map_svg: map_svg},
            attrs
          )
        )

      story
    end

    test "upgrades untouched v1 maps and rolls them back" do
      untouched =
        for {slug, _module} <- @games,
            into: %{},
            do: {slug, story_with(MapArtwork.read!(slug, 1))}

      edited = story_with(MapArtwork.read!("neon-republic", 1) <> "<circle r=\"4\"/>")
      custom = story_with(~s(<rect width="10" height="10"/>))

      resized =
        story_with(MapArtwork.read!("arkham-adrift", 1), %{map_width: 1200, map_height: 700})

      assert :ok = UpgradeBuiltinGdrMaps.upgrade(Repo, 1, 2)

      for {slug, story} <- untouched do
        assert Repo.reload!(story).map_svg == MapArtwork.read!(slug, 2)
      end

      assert Repo.reload!(edited).map_svg == edited.map_svg
      assert Repo.reload!(custom).map_svg == custom.map_svg
      assert Repo.reload!(resized).map_svg == resized.map_svg

      assert :ok = UpgradeBuiltinGdrMaps.upgrade(Repo, 2, 1)

      for {slug, story} <- untouched do
        assert Repo.reload!(story).map_svg == MapArtwork.read!(slug, 1)
      end

      assert Repo.reload!(resized).map_svg == resized.map_svg
    end
  end
end
