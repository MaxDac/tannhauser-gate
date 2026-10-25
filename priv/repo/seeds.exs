# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It is idempotent: it creates the platform admin, the default "Tannhauser
# Gate" GDR, the second "Neon Republic" GDR and a GM owner for each one only
# if they don't exist yet. Seeded accounts must change their password at their
# first login. Credentials can be overridden with the ADMIN_*, TG_GM_* and
# NR_GM_* (EMAIL / USERNAME / PASSWORD) env vars.

%{story: story, neon_republic: %{story: neon}} = TannhauserGate.Seeds.run()

for gdr <- [story, neon] do
  IO.puts("Seeded GDR #{inspect(gdr.name)} with #{length(gdr.locations)} rooms")
end

IO.puts("\nSeeded accounts (password must be changed at first login):")

for {label, creds} <- TannhauserGate.Seeds.credentials() do
  IO.puts("  #{label}: #{creds.username} <#{creds.email}>")
end
