defmodule TannhauserGate.Seeds do
  @moduledoc """
  Idempotent seed data: the default "Tannhauser Gate" story with its city map
  and rooms, a default admin account and a few forum sections.

  All lore and artwork here is original and only *inspired* by the
  neo-noir/cyberpunk genre.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.{Accounts, Forum, Repo, Stories}
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Forum.Section
  alias TannhauserGate.Stories.Location

  @story_name "Tannhauser Gate"
  @default_admin_email "admin@tannhauser.gate"
  @default_admin_username "admin"
  @default_admin_password "change-me-tannhauser-2121"

  def default_admin_email, do: @default_admin_email
  def default_admin_password, do: @default_admin_password

  def run do
    admin = seed_admin()
    story = seed_story()
    seed_sections()
    %{admin: admin, story: story}
  end

  ## Admin

  def seed_admin do
    email = System.get_env("ADMIN_EMAIL") || @default_admin_email
    password = System.get_env("ADMIN_PASSWORD") || @default_admin_password

    user =
      case Accounts.get_user_by_email(email) do
        nil ->
          {:ok, user} =
            Accounts.register_user(%{
              username: System.get_env("ADMIN_USERNAME") || @default_admin_username,
              email: email,
              password: password
            })

          user

        user ->
          user
      end

    user
    |> User.confirm_changeset()
    |> Repo.update!()
    |> then(fn user ->
      {:ok, user} = Accounts.set_user_role(user, "admin")
      user
    end)
  end

  ## Story

  def seed_story do
    story =
      case Stories.get_story_by_name(@story_name) do
        nil ->
          {:ok, story} =
            Stories.create_story(%{
              name: @story_name,
              summary: summary(),
              world_background: world_background(),
              customs: customs(),
              map_svg: map_svg(),
              map_width: 1000,
              map_height: 700,
              is_default: true
            })

          story

        story ->
          story
      end

    existing = MapSet.new(Stories.list_locations(story), & &1.name)

    for attrs <- locations(), not MapSet.member?(existing, attrs.name) do
      {:ok, %Location{}} = Stories.create_location(story, attrs)
    end

    Stories.get_story!(story.id)
  end

  ## Forum

  def seed_sections do
    sections = [
      %{
        name: "Out of Character",
        description: "Talk about anything outside the story.",
        position: 0
      },
      %{
        name: "Story & Lore",
        description: "Questions and theories about Neo-Meridian.",
        position: 1
      },
      %{name: "Character Workshop", description: "Share and refine your characters.", position: 2}
    ]

    for attrs <- sections, is_nil(Repo.get_by(Section, name: attrs.name)) do
      {:ok, _} = Forum.create_section(attrs)
    end

    :ok
  end

  ## Lore

  defp summary do
    "Neo-Meridian, 2121. Acid rain never stops, the ads never sleep, and somewhere " <>
      "beyond the orbital relay called the Tannhauser Gate, the Echoes are coming home."
  end

  defp world_background do
    """
    Neo-Meridian is a vertical city of forty million souls, stacked on the drowned bones of three older cities. The sun is a rumour: a permanent brown haze, lit from below by holographic advertising, hides the sky. Rain falls almost every day, warm and faintly acidic, and the streets glow a sickly phosphor green in its reflections.

    The Ascendant Corporation built the city's upper tiers and owns most of what happens there. Its greatest product is the Echo: a synthetic human, grown rather than built, indistinguishable from people born of flesh except for a lifespan capped at six years and a pattern of irises that only a Lumen scan can read. Echoes labour in the offworld colonies, mining ice moons and terraforming dead rocks beyond the Tannhauser Gate, the great relay ring at the edge of the system through which every colony ship must pass.

    Echoes are forbidden on Earth. Those who come back anyway, carrying stolen memories and a desperate hunger for more time, are hunted by the Retirement Unit of Precinct 9. Officers of the unit are called "Wardens". Some say a few Wardens are Echoes themselves, and do not know it.

    Below the tiers lies the Undercity: canals, markets and the abandoned Old Arcade district, where a person can buy a new name, a forged memory, or a ticket to anywhere. Above them, the Zenith Spire of the Ascendant Corporation pierces the clouds, and its founder has not been seen in public for thirty years.
    """
  end

  defp customs do
    """
    - Never ask someone where they were born. Memories can be bought, and the question is considered an accusation.
    - Rain cloaks are worn by everyone; going uncovered marks you as an offworlder or a fool.
    - Street vendors speak "Gutterline", a creole of a dozen languages. A shared bowl of noodles seals any bargain.
    - Paper photographs are treasured: they are the only proof of a past that cannot be edited.
    - Origami figures left at a scene are a Warden's signature, a silent "I was here".
    - Offworld recruitment ships drift overhead day and night, promising a new life beyond the Gate.
    """
  end

  ## Map

  @doc """
  The rooms (locations) of the default story. Polygons are convex, in a
  1000x700 coordinate space matching `map_svg/0`.
  """
  def locations do
    [
      %{
        name: "Zenith Spire",
        description:
          "The Ascendant Corporation's ziggurat headquarters. Flames burst from the gas vents on its flanks; the penthouse office is lit by a fake sunset.",
        area: "430,40 570,40 600,170 400,170",
        color: "#c8f56a"
      },
      %{
        name: "Precinct 9 Station",
        description:
          "Police headquarters and home of the Retirement Unit. Spinner pads on the roof, interrogation rooms in the basement.",
        area: "90,90 260,90 260,220 90,220",
        color: "#4ae08a"
      },
      %{
        name: "Neon Bazaar",
        description:
          "A maze of stalls under flickering signs: genetic eye makers, artificial snakes, synthetic owls. Everything is for sale.",
        area: "380,250 620,250 620,400 380,400",
        color: "#3ff0c0"
      },
      %{
        name: "Ozu's Noodle Counter",
        description:
          "Four stools, one cook, endless steam. The cook never asks questions and always remembers faces.",
        area: "660,260 790,260 790,370 660,370",
        color: "#9be35a"
      },
      %{
        name: "Old Arcade Hotel",
        description:
          "A once-grand hotel in the abandoned Old Arcade district. Mannequins, broken automata and dust; perfect for those who wish to disappear.",
        area: "90,300 280,300 280,460 90,460",
        color: "#6fbf8f"
      },
      %{
        name: "Lacuna Memory Atelier",
        description:
          "A quiet clinic where artisans craft memories for Echoes, and sometimes for humans who want to forget.",
        area: "820,110 950,110 950,240 820,240",
        color: "#9bf5bf"
      },
      %{
        name: "Undercity Docks",
        description:
          "Black canals where cargo barges and smugglers meet. The water glows faintly from runoff.",
        area: "300,520 560,520 560,650 300,650",
        color: "#2fb89a"
      },
      %{
        name: "Offworld Spaceport Gate 7",
        description:
          "Departure gate for colony shuttles bound for the Tannhauser Gate relay. Lumen scanners at every turnstile.",
        area: "640,470 920,470 920,640 640,640",
        color: "#e0f59a"
      },
      %{
        name: "Sentinel Tower Rooftop",
        description:
          "The highest public rooftop in the lower tiers. Rain, wind, and the best view of the Spire. Legends end here.",
        area: "640,60 760,60 760,180 640,180",
        color: "#d6f0e0"
      }
    ]
  end

  @doc """
  Original SVG artwork for the city of Neo-Meridian (1000x700). Rooms are
  overlaid at runtime from the locations' polygons.
  """
  def map_svg do
    """
    <defs>
      <linearGradient id="tg-sky" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="#050a07"/>
        <stop offset="100%" stop-color="#0e1c14"/>
      </linearGradient>
      <pattern id="tg-grid" width="40" height="40" patternUnits="userSpaceOnUse">
        <path d="M40 0H0V40" fill="none" stroke="#4ae08a" stroke-opacity="0.07" stroke-width="1"/>
      </pattern>
      <pattern id="tg-rain" width="24" height="24" patternUnits="userSpaceOnUse" patternTransform="rotate(18)">
        <line x1="0" y1="0" x2="0" y2="10" stroke="#9bf5bf" stroke-opacity="0.1" stroke-width="1"/>
      </pattern>
    </defs>
    <rect width="1000" height="700" fill="url(#tg-sky)"/>
    <rect width="1000" height="700" fill="url(#tg-grid)"/>
    <path d="M0 500 C 150 470, 250 560, 400 500 S 650 450, 1000 520 L1000 700 L0 700 Z" fill="#0a1f16" opacity="0.9"/>
    <path d="M0 500 C 150 470, 250 560, 400 500 S 650 450, 1000 520" fill="none" stroke="#2fb89a" stroke-opacity="0.5" stroke-width="2"/>
    <g stroke="#2c8f58" stroke-opacity="0.45" stroke-width="6" fill="none" stroke-linecap="round">
      <path d="M0 240 H1000"/>
      <path d="M330 0 V700"/>
      <path d="M800 0 V460"/>
      <path d="M0 470 L620 420 L1000 440"/>
    </g>
    <g stroke="#86e0b0" stroke-opacity="0.2" stroke-width="2" fill="none" stroke-dasharray="6 8">
      <path d="M0 240 H1000"/>
      <path d="M330 0 V700"/>
      <path d="M800 0 V460"/>
    </g>
    <g fill="#142219" stroke="#24382b" stroke-width="1">
      <rect x="20" y="20" width="50" height="190"/>
      <rect x="290" y="30" width="30" height="180"/>
      <rect x="610" y="200" width="40" height="30"/>
      <rect x="850" y="270" width="110" height="160"/>
      <rect x="20" y="490" width="240" height="190"/>
      <rect x="350" y="430" width="200" height="60"/>
    </g>
    <g fill="#9be35a" opacity="0.45">
      <rect x="30" y="40" width="4" height="4"/><rect x="50" y="80" width="4" height="4"/>
      <rect x="300" y="60" width="4" height="4"/><rect x="870" y="300" width="4" height="4"/>
      <rect x="920" y="360" width="4" height="4"/><rect x="60" y="540" width="4" height="4"/>
      <rect x="160" y="600" width="4" height="4"/><rect x="420" y="450" width="4" height="4"/>
    </g>
    <circle cx="500" cy="105" r="140" fill="#4ae08a" opacity="0.06"/>
    <rect width="1000" height="700" fill="url(#tg-rain)"/>
    <text x="980" y="690" text-anchor="end" font-family="monospace" font-size="14" fill="#86e0b0" fill-opacity="0.6">NEO-MERIDIAN · SECTOR 9 · 2121</text>
    """
  end
end
