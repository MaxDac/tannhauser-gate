# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It is idempotent: it creates the default "Tannhauser Gate" story, its map
# and rooms, the default admin (ADMIN_EMAIL / ADMIN_PASSWORD env vars) and the
# forum sections only if they don't exist yet.

%{admin: admin, story: story} = TannhauserGate.Seeds.run()

IO.puts("Seeded story #{inspect(story.name)} with #{length(story.locations)} rooms")
IO.puts("Admin account: #{admin.email}")
