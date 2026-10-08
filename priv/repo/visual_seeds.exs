# Deterministic fixture data for the Playwright screenshot tests.
#
# Run against an empty, freshly seeded database (see e2e/README section in the
# project README):
#
#     DEV_DATABASE=tannhauser_gate_visual mix ecto.reset
#     DEV_DATABASE=tannhauser_gate_visual mix run priv/repo/visual_seeds.exs
#
# Every row gets a fixed timestamp at the end, so rendered dates never change.

alias TannhauserGate.{Accounts, Characters, Chat, Forum, Repo, Seeds, Storage, Stories}
alias TannhauserGate.Forum.Section

%{story: story} = Seeds.run()

player_email = "player@tannhauser.gate"
player_password = "more-human-than-human"

player =
  Accounts.get_user_by_email(player_email) ||
    elem(Accounts.register_user(%{email: player_email, password: player_password}), 1)

avatar = Storage.store_upload!(Path.expand("../../e2e/fixtures/avatar.png", __DIR__), "avatar.png")

{:ok, deckard} =
  Characters.create_character(
    player,
    %{
      "name" => "Rick Deckard",
      "story_id" => story.id,
      "description" => "Trench coat, tired eyes, a taste for noodles.",
      "background" =>
        "A former Warden of Precinct 9, pulled back for one last retirement. " <>
          "He dreams of unicorns and does not ask why."
    },
    avatar
  )

{:ok, _gaff} =
  Characters.create_character(player, %{
    "name" => "Gaff",
    "story_id" => story.id,
    "description" => "Cane, bowler hat, origami.",
    "background" => "Speaks Gutterline and leaves paper animals behind."
  })

room = Enum.find(Stories.list_locations(story), &(&1.name == "Ozu's Noodle Counter"))

for body <- [
      "Four. Two, two, four.",
      "No, two is enough. Two, two, four and noodles.",
      "Have you ever retired a human by mistake?"
    ] do
  {:ok, _} = Chat.create_message(player, room, %{character_id: deckard.id, body: body})
end

section = Repo.get_by!(Section, name: "Out of Character")

{:ok, topic} =
  Forum.create_topic(player, section, %{title: "Origami unicorns", body: "Did you make this?"})

{:ok, _} = Forum.create_post(player, topic, %{body: "It's too bad she won't live."})

# Fixed, monotonic timestamps: 2121-11-03 21:00 UTC plus one minute per row id.
for table <-
      ~w(users stories locations characters messages forum_sections forum_topics forum_posts) do
  Repo.query!(
    """
    UPDATE #{table}
    SET inserted_at = TIMESTAMP '2121-11-03 21:00:00' + id * INTERVAL '1 minute',
        updated_at = TIMESTAMP '2121-11-03 21:00:00' + id * INTERVAL '1 minute'
    """,
    []
  )
end

IO.puts("Visual fixtures ready (player: #{player_email})")
