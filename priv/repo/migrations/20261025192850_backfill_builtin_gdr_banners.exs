defmodule TannhauserGate.Repo.Migrations.BackfillBuiltinGdrBanners do
  use Ecto.Migration

  # Gives the built-in GDRs created before they had artwork their directory
  # banner. Runs once and only fills an empty banner, so a GM who replaces or
  # removes it later keeps their choice.
  @banners [
    {"Tannhauser Gate", "/images/gdr/tannhauser-gate-banner.svg"},
    {"Neon Republic", "/images/gdr/neon-republic-banner.svg"}
  ]

  def up do
    for {name, path} <- @banners do
      execute(fn ->
        repo().query!(
          "UPDATE stories SET banner_path = $1 WHERE name = $2 AND banner_path IS NULL",
          [path, name]
        )
      end)
    end
  end

  def down do
    for {name, path} <- @banners do
      execute(fn ->
        repo().query!(
          "UPDATE stories SET banner_path = NULL WHERE name = $1 AND banner_path = $2",
          [name, path]
        )
      end)
    end
  end
end
