defmodule TannhauserGate.Seeds do
  @moduledoc """
  Idempotent seed data: the platform admin, the two sample GDRs and their GM
  owners.

    * "Tannhauser Gate" (`TannhauserGate.Seeds.DefaultGdr`) - the default GDR,
      a neo-noir city of synthetic Echoes and the Wardens who hunt them;
    * "Neon Republic" (`TannhauserGate.Seeds.NeonRepublic`) - a sprawl of
      console cowboys, orbital clans and rogue AIs.

  Seeded accounts are created confirmed and flagged to change their password
  at the first access; their credentials can be overridden with environment
  variables (see `credentials/0`). All lore and artwork is original and only
  *inspired* by the cyberpunk genre.
  """

  alias TannhauserGate.Seeds.{DefaultGdr, Helpers, NeonRepublic}

  @admin %{
    env: "ADMIN",
    email: "admin@tannhauser.gate",
    username: "admin",
    password: "change-me-tannhauser-2121"
  }

  def default_admin_email, do: @admin.email
  def default_admin_password, do: @admin.password

  @doc """
  Seeds everything. Returns the admin, the default story (`:story`) and its
  GM owner (`:gm`), and the Neon Republic story and GM under `:neon_republic`.
  """
  def run do
    admin = seed_admin()
    %{story: story, gm: gm} = DefaultGdr.run(admin)
    neon_republic = NeonRepublic.run(admin)
    %{admin: admin, story: story, gm: gm, neon_republic: neon_republic}
  end

  @doc """
  The platform admin (`ADMIN_EMAIL`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`).
  """
  def seed_admin, do: Helpers.seed_user(@admin, admin: true)

  @doc """
  The seeded accounts and their (env-resolved) initial credentials, all to
  be changed at the first access.
  """
  def credentials do
    [
      {"Platform admin", Helpers.credentials(@admin)},
      {"#{DefaultGdr.story_name()} GM", DefaultGdr.gm_credentials()},
      {"#{NeonRepublic.story_name()} GM", NeonRepublic.gm_credentials()}
    ]
  end

  @doc "The rooms of the default story (see `DefaultGdr.locations/0`)."
  defdelegate locations, to: DefaultGdr

  @doc "The map of the default story (see `DefaultGdr.map_svg/0`)."
  defdelegate map_svg, to: DefaultGdr
end
