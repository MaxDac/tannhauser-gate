defmodule TannhauserGate.Seeds.MapArtwork do
  @moduledoc """
  Original map artwork of the built-in GDRs.

  The artwork lives in `priv/map_artwork/<slug>.v<version>.svg` as inner SVG
  markup (no `<svg>` wrapper) for a 1000x700 viewBox. Released versions are
  immutable, so data migrations can recognize maps a GM never edited and
  upgrade them safely.
  """

  @current_version 2

  @slugs ~w(tannhauser-gate neon-republic arkham-adrift toronto-by-night)

  @doc "The version the seeds install."
  def current_version, do: @current_version

  @doc "The slugs of the built-in GDRs with artwork."
  def slugs, do: @slugs

  @doc "Reads the artwork of `slug` at `version` (the current one by default)."
  def read!(slug, version \\ @current_version) when slug in @slugs do
    File.read!(path(slug, version))
  end

  @doc "The path of the artwork file of `slug` at `version`."
  def path(slug, version) do
    Application.app_dir(:tannhauser_gate, ["priv", "map_artwork", "#{slug}.v#{version}.svg"])
  end
end
