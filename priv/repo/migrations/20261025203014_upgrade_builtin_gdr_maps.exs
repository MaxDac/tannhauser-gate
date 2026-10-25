defmodule TannhauserGate.Repo.Migrations.UpgradeBuiltinGdrMaps do
  use Ecto.Migration

  # Swaps the original map artwork of the built-in GDRs for the richer v2
  # maps. Only maps still identical to the v1 artwork (and still 1000x700) are
  # upgraded, so a GM who edited or replaced the map keeps it. The artwork
  # versions are immutable files in priv/map_artwork.
  @slugs ~w(tannhauser-gate neon-republic arkham-adrift toronto-by-night)

  def up, do: execute(fn -> upgrade(repo(), 1, 2) end)

  def down, do: execute(fn -> upgrade(repo(), 2, 1) end)

  @doc false
  def upgrade(repo, from, to) do
    for slug <- @slugs do
      repo.query!(
        "UPDATE stories SET map_svg = $1 " <>
          "WHERE map_svg = $2 AND map_width = 1000 AND map_height = 700",
        [artwork(slug, to), artwork(slug, from)],
        log: false
      )
    end

    :ok
  end

  defp artwork(slug, version) do
    :tannhauser_gate
    |> Application.app_dir(["priv", "map_artwork", "#{slug}.v#{version}.svg"])
    |> File.read!()
  end
end
