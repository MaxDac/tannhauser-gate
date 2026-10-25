defmodule TannhauserGate.Seeds.TorontoByNight do
  @moduledoc """
  Idempotent seed data for the "Toronto by Night" GDR: a modern gothic-punk
  chronicle of vampires in Toronto, 2026. Seeds its GM owner, banner, map and
  rooms, forum sections, a full V5-style sheet, Hunger dice, every optional
  module and a cast of named NPCs with original portraits.

  This is an unofficial fan setting for play in the style of *Vampire: The
  Masquerade* (5th edition); Vampire: The Masquerade is a trademark of its
  owner. All lore, rules text, maps and artwork here are original.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.{
    Bank,
    Calendars,
    Forum,
    Guide,
    Guilds,
    Items,
    Origins,
    Quests,
    Repo,
    Sheet,
    Stories,
    Trackers,
    Weather,
    Zones
  }

  alias TannhauserGate.Boards.{Announcement, Board, Notice}
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Diary.Entry
  alias TannhauserGate.Esiti.{Esito, Message}
  alias TannhauserGate.Forum.Section
  alias TannhauserGate.Quests.Quest
  alias TannhauserGate.Seeds.Helpers
  alias TannhauserGate.Stories.Location

  @story_name "Toronto by Night"
  @banner_path "/images/gdr/toronto-by-night-banner.svg"
  @avatar_dir "/images/gdr/toronto-by-night"

  @gm %{
    env: "TBN_GM",
    email: "gm@toronto.bynight",
    username: "tbn_gm",
    password: "change-me-toronto-by-night-2026"
  }

  @sample_npc "Céleste Marchand"
  @sample_esito "The ferry that crossed at 4 a.m."
  @sample_quest "Ashes on the Islands"
  @sample_announcement "Welcome to Toronto by Night"

  def story_name, do: @story_name
  def banner_path, do: @banner_path

  @doc "The default credentials of the GM owning this GDR (env-overridable)."
  def gm_credentials, do: Helpers.credentials(@gm)

  @doc """
  Seeds the GDR and its GM owner; `admin` signs the sample content. Returns
  `%{story: story, gm: gm}`.
  """
  def run(admin) do
    gm = Helpers.seed_user(@gm, gm: true)
    story = seed_story()
    story = Helpers.assign_owner(story, gm)
    seed_sections(story)
    seed_sheet(story)
    seed_jobs(story)
    seed_guide(story)
    seed_zones(story)
    story = seed_origins(story)
    seed_trackers(story)
    story = seed_dice(story)
    seed_actions(story)
    story = seed_items(story)
    story = seed_guilds(story)
    story = seed_chat_rp(story)
    story = seed_esiti_and_quests(story, admin)
    story = seed_diary_and_boards(story, admin)
    story = seed_calendar_and_weather(story)
    story = seed_reports(story)
    story = seed_listing(story)
    %{story: story, gm: gm}
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
              status: "published",
              theme: "nocturne",
              currency_name: "loonies",
              map_svg: map_svg(),
              map_width: 1000,
              map_height: 700,
              is_default: false,
              max_characters_per_user: 2
            })

          # The banner is set only once: a GM may later replace or remove it.
          {:ok, story} = Stories.set_banner(story, @banner_path)
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

  def seed_sections(story) do
    sections = [
      %{name: "Out of Character", description: "Talk between players.", position: 0},
      %{
        name: "Kindred Lore",
        description: "Questions about the Kindred of Toronto, the Traditions and the rules.",
        position: 1
      },
      %{
        name: "Character Coterie",
        description: "Build your Kindred, find a coterie and share your Touchstones.",
        position: 2
      }
    ]

    for attrs <- sections, is_nil(Repo.get_by(Section, story_id: story.id, name: attrs.name)) do
      {:ok, _} = Forum.create_section(story, attrs)
    end

    :ok
  end

  ## Sheet and jobs

  @doc "Nine attributes, twenty-seven skills and twelve disciplines (powers)."
  def sheet_items do
    attribute = fn name, description ->
      %{kind: "attribute", name: name, description: description, min_value: 1, max_value: 5}
    end

    skill = fn name, description ->
      %{kind: "skill", name: name, description: description, min_value: 0, max_value: 5}
    end

    power = fn name, description ->
      %{kind: "power", name: name, description: description, min_value: 0, max_value: 5}
    end

    [
      # Physical
      attribute.("Strength", "Raw muscle: lifting, breaking, hitting hard."),
      attribute.("Dexterity", "Speed, balance and fine control."),
      attribute.("Stamina", "Toughness. How much punishment your dead body shrugs off."),
      # Social
      attribute.("Charisma", "Charm and the pull that makes people want to follow you."),
      attribute.("Manipulation", "Steering people where you want them without them noticing."),
      attribute.("Composure", "Keeping your face still when the Beast is clawing at it."),
      # Mental
      attribute.("Intelligence", "Memory, reasoning and knowledge."),
      attribute.("Wits", "Quick thinking and reacting before the trap closes."),
      attribute.("Resolve", "Focus and stubbornness. The will to keep going."),
      # Physical skills
      skill.("Athletics", "Running, climbing, jumping and swimming in a cold lake."),
      skill.("Brawl", "Fists, teeth and dirty fighting."),
      skill.("Craft", "Making and mending things: art, carpentry, tattoos, cocktails."),
      skill.("Drive", "Cars, bikes and the 401 at three in the morning."),
      skill.("Firearms", "Pistols, rifles and keeping your hand steady."),
      skill.("Larceny", "Locks, alarms, pickpocketing and breaking and entering."),
      skill.("Melee", "Knives, bats, stakes and swords."),
      skill.("Stealth", "Not being seen, heard or remembered."),
      skill.("Survival", "Tracking, hiding and finding shelter before dawn."),
      # Social skills
      skill.("Animal Ken", "Raccoons, dogs and the rats under Union Station."),
      skill.("Etiquette", "Manners at Elysium, and at every other table."),
      skill.("Insight", "Reading moods, lies and motives."),
      skill.("Intimidation", "Fear as a tool, used openly or by suggestion."),
      skill.("Leadership", "Getting a coterie, a gang or a crowd to follow you."),
      skill.("Performance", "Music, dance, acting and holding an audience."),
      skill.("Persuasion", "Winning people over with argument and appeal."),
      skill.("Streetwise", "Knowing the city's corners, rumours and dealers."),
      skill.("Subterfuge", "Lying well, and keeping a lie alive."),
      # Mental skills
      skill.("Academics", "History, art, law and the humanities."),
      skill.("Awareness", "Noticing the shadow on the stairs before it moves."),
      skill.("Finance", "Money, markets and following the money."),
      skill.("Investigation", "Clues, records and putting the pieces together."),
      skill.("Medicine", "Anatomy, first aid, and knowing where the arteries run."),
      skill.("Occult", "Rituals, legends and the hidden history of the Kindred."),
      skill.("Politics", "City Hall, the Court and the deals behind both."),
      skill.("Science", "Chemistry, biology and the rest of the lab."),
      skill.("Technology", "Computers, phones, cameras and how to erase what they saw."),
      # Disciplines
      power.("Animalism", "Kinship with beasts, and mastery of the Beast within."),
      power.("Auspex", "Heightened senses, visions and reading other people's minds."),
      power.("Blood Sorcery", "Rituals that bend vitae to the caster's will."),
      power.("Celerity", "Speed beyond human limits."),
      power.("Dominate", "Commands and stolen memories, pressed into weaker minds."),
      power.("Fortitude", "Resistance to harm, even fire and sunlight, for a while."),
      power.("Obfuscate", "Going unseen, or being seen as someone else."),
      power.("Oblivion", "Shadows and the restless dead, called from the other side."),
      power.("Potence", "Strength enough to break bone and steel."),
      power.("Presence", "Awe, dread and adoration that bend a crowd's mood."),
      power.("Protean", "Changing the body: claws, earth-meld and beast shapes."),
      power.(
        "Thin-Blood Alchemy",
        "Brewing strange effects from blood, chemistry and stubbornness."
      )
    ]
  end

  def seed_sheet(story) do
    if Sheet.list_items(story) == [] do
      sheet_items()
      |> Enum.with_index()
      |> Enum.each(fn {attrs, index} ->
        {:ok, _} = Sheet.create_item(story, Map.put(attrs, :position, index))
      end)
    end

    :ok
  end

  @doc "Night jobs and their pay (per pay interval)."
  def jobs do
    [
      %{
        name: "Night Security Guard",
        description: "Walk empty towers on Bay Street and watch the monitors.",
        pay: 55
      },
      %{
        name: "Bartender at Club Vesper",
        description: "Pour drinks, read the room and keep the back rooms quiet.",
        pay: 60
      },
      %{
        name: "Overnight Courier",
        description: "Deliver whatever needs delivering after midnight. No questions asked.",
        pay: 45
      },
      %{
        name: "Hospital Night Porter",
        description: "Push trolleys at St. Michael's, and keep an eye on the blood bank.",
        pay: 50
      },
      %{
        name: "Gallery Night Curator",
        description: "Hang shows and host openings for patrons who never visit by day.",
        pay: 65
      },
      %{
        name: "Rideshare Driver",
        description: "Drive the city all night. Every passenger is a chance to feed.",
        pay: 40
      }
    ]
  end

  def seed_jobs(story) do
    existing = MapSet.new(Bank.list_jobs(story), & &1.name)

    for attrs <- jobs(), not MapSet.member?(existing, attrs.name) do
      {:ok, _} = Bank.create_job(story, attrs)
    end

    :ok
  end

  ## Guide and zones

  def seed_guide(story) do
    if Guide.list_sections(story) == [] do
      {:ok, world} = Guide.create_section(story, %{title: "The city", position: 0})

      [
        {"Background", world_background()},
        {"The Masquerade and the Traditions", traditions()},
        {"Hunger and the Beast", hunger()},
        {"Factions of Toronto", factions()},
        {"Rules", rules()},
        {"Customs", customs()},
        {"Glossary", glossary()}
      ]
      |> Enum.with_index()
      |> Enum.each(fn {{title, body}, index} ->
        {:ok, _} =
          Guide.create_page(story, %{
            section_id: world.id,
            title: title,
            body: body,
            position: index
          })
      end)
    end

    :ok
  end

  def seed_zones(story) do
    if Zones.list_zones(story) == [] do
      {:ok, _} = Zones.create_property(story, %{name: "Heat", slug: "heat", default_value: 2})

      {:ok, _} =
        Zones.create_property(story, %{name: "Danger", slug: "danger", default_value: 2})

      locations = Map.new(Stories.list_locations(story), &{&1.name, &1})

      Enum.each(zones(), &seed_zone(story, locations, &1))
    end

    :ok
  end

  defp seed_zone(story, locations, {name, description, values, rooms}) do
    {:ok, zone} =
      Zones.create_zone(story, %{name: name, description: description, values: values})

    for {_name, location} <- Map.take(locations, rooms) do
      {:ok, _} = Stories.update_location(location, %{zone_id: zone.id})
    end
  end

  defp zones do
    [
      {"The Downtown Domain",
       "Camarilla ground from Yorkville to the lake. Cameras on every corner and the " <>
         "Sheriff's people watching them: hunting here is safe and slow.",
       %{"heat" => 4, "danger" => 1},
       [
         "Elysium: The Gilded Hour",
         "The Crown Room",
         "Union Station Undercity",
         "Distillery District"
       ]},
      {"The Free Streets",
       "Kensington, Queen West and the old east end. The Anarchs hold them, the bars stay " <>
         "open late and nobody calls the police.", %{"heat" => 2, "danger" => 3},
       ["Kensington Market", "Club Vesper", "The Necropolis"]},
      {"The Ravines and the Lake",
       "Wild green scars through the city, the islands and the cliffs east of town. " <>
         "Nobody claims them. Something else does.", %{"heat" => 1, "danger" => 5},
       ["Don Valley Ravine", "Toronto Islands", "Scarborough Bluffs"]}
    ]
  end

  ## Origins

  def seed_origins(story) do
    if Origins.list_groups(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :origins, true)
      slugs = Sheet.slugs(story)

      {:ok, clan} =
        Origins.create_group(story, %{
          name: "Clan",
          description: "The blood of your Sire, with its gifts and its curse.",
          required: true,
          position: 0
        })

      seed_options(story, clan, slugs, clans())

      {:ok, predator} =
        Origins.create_group(story, %{
          name: "Predator type",
          description: "How you hunt, and what it costs the people you feed on.",
          required: true,
          position: 1
        })

      seed_options(story, predator, slugs, predator_types())

      story
    else
      story
    end
  end

  defp seed_options(story, group, slugs, options) do
    for {attrs, index} <- Enum.with_index(options) do
      {:ok, _} =
        Origins.create_option(
          story,
          attrs
          |> Map.put(:group_id, group.id)
          |> Map.put(:position, index)
          |> Map.update!(:bonuses, &Map.take(&1, slugs))
        )
    end
  end

  defp clans do
    [
      %{
        name: "Banu Haqim",
        bonuses: %{"celerity" => 1, "obfuscate" => 1},
        description:
          "Judges and blades, bound by a strict code. In Toronto they keep to themselves, " <>
            "settle debts for a price and drink only from the guilty, or say they do."
      },
      %{
        name: "Brujah",
        bonuses: %{"potence" => 1, "presence" => 1},
        description:
          "Rebels with a cause and a temper to match. Most of the Free Streets' Barons are " <>
            "Brujah, and most of the city's riots started at their tables."
      },
      %{
        name: "Gangrel",
        bonuses: %{"fortitude" => 1, "protean" => 1},
        description:
          "Wanderers who take after the beasts. The ravines belong to them, and to Mother Ash."
      },
      %{
        name: "Hecata",
        requires_approval: true,
        bonuses: %{"oblivion" => 1, "auspex" => 1},
        description:
          "Families of necromancers who speak with the dead and trade in what they say. " <>
            "They have quietly bought the Necropolis.\n\n*Requires the masters' approval.*"
      },
      %{
        name: "Lasombra",
        requires_approval: true,
        bonuses: %{"oblivion" => 1, "dominate" => 1},
        description:
          "Shadow-masters newly arrived in the Camarilla, and not trusted there. Their " <>
            "reflections are faint, their ambitions are not.\n\n*Requires the masters' approval.*"
      },
      %{
        name: "Malkavian",
        bonuses: %{"auspex" => 1, "dominate" => 1},
        description:
          "Seers whose blood carries madness. They see what is really there; it is just " <>
            "that what is really there is unbearable."
      },
      %{
        name: "The Ministry",
        bonuses: %{"presence" => 1, "obfuscate" => 1},
        description:
          "Tempters and liberators who preach freedom from every chain, including the " <>
            "ones you wanted to keep."
      },
      %{
        name: "Nosferatu",
        bonuses: %{"obfuscate" => 1, "animalism" => 1},
        description:
          "Twisted by the Embrace and hidden from human eyes. They own the tunnels and the " <>
            "PATH after closing time, and they know everybody's secrets."
      },
      %{
        name: "Toreador",
        bonuses: %{"presence" => 1, "celerity" => 1},
        description:
          "Lovers of beauty and art, and arbiters of taste at Elysium. Their Keeper, " <>
            "Céleste Marchand, decides who is welcome at the Gilded Hour."
      },
      %{
        name: "Tremere",
        bonuses: %{"blood_sorcery" => 1, "auspex" => 1},
        description:
          "Blood sorcerers whose old pyramid has collapsed. The Toronto chantry lost its " <>
            "regent, and its secrets are up for grabs."
      },
      %{
        name: "Tzimisce",
        bonuses: %{"protean" => 1, "animalism" => 1},
        description:
          "Possessive lords who shape flesh and must sleep on their own earth. They are " <>
            "few in Toronto, and everyone knows where each of them lives."
      },
      %{
        name: "Ventrue",
        bonuses: %{"dominate" => 1, "presence" => 1},
        description:
          "Kings and CEOs of the night, with expensive tastes. Prince Adelaide Rourke rules " <>
            "Toronto from the Crown Room."
      },
      %{
        name: "Caitiff",
        bonuses: %{"streetwise" => 1, "survival" => 1},
        description:
          "Clanless, Embraced and abandoned. No clan speaks for you, so you learned to " <>
            "speak for yourself."
      },
      %{
        name: "Thin-blood",
        bonuses: %{"thin_blood_alchemy" => 1, "science" => 1},
        description:
          "Barely Kindred: you can still walk in daylight, a little, and eat food, " <>
            "badly. Many elders would rather you didn't exist."
      }
    ]
  end

  defp predator_types do
    [
      %{
        name: "Alleycat",
        bonuses: %{"brawl" => 1, "intimidation" => 1},
        description:
          "You take blood by force, in alleys and parking garages. Quick, ugly, effective."
      },
      %{
        name: "Bagger",
        bonuses: %{"larceny" => 1, "streetwise" => 1},
        description:
          "Stolen blood bags, hospital fridges, the black market. No feeding on the living, " <>
            "and no warmth either."
      },
      %{
        name: "Blood Leech",
        requires_approval: true,
        bonuses: %{"brawl" => 1, "stealth" => 1},
        description:
          "You feed on other Kindred. It is a crime, it is addictive, and if the Court " <>
            "finds out you are finished.\n\n*Requires the masters' approval.*"
      },
      %{
        name: "Cleaver",
        bonuses: %{"persuasion" => 1, "subterfuge" => 1},
        description:
          "You hide your nature from a family, mortal or chosen, and feed on them quietly. " <>
            "One slip and you lose everything."
      },
      %{
        name: "Consensualist",
        bonuses: %{"medicine" => 1, "persuasion" => 1},
        description:
          "You only drink with permission, from people who think you are something else: " <>
            "a donor, a kink, a trial."
      },
      %{
        name: "Farmer",
        bonuses: %{"animal_ken" => 1, "animalism" => 1},
        description:
          "You feed on animals to protect your Humanity. It never quite satisfies the Beast."
      },
      %{
        name: "Osiris",
        bonuses: %{"performance" => 1, "presence" => 1},
        description:
          "You are a celebrity, a DJ or a cult leader, and your followers line up to be bitten."
      },
      %{
        name: "Sandman",
        bonuses: %{"stealth" => 1, "medicine" => 1},
        description:
          "You slip into homes and feed on the sleeping. They wake up tired, and nothing more."
      },
      %{
        name: "Siren",
        bonuses: %{"persuasion" => 1, "subterfuge" => 1},
        description:
          "You seduce your prey on the dance floor or in the back seat. Leaving the bed " <>
            "before they wake is the hard part."
      }
    ]
  end

  ## Mechanics: trackers, dice and periodic actions

  @doc """
  Health and Willpower (superficial/aggravated damage), Hunger (the Beast's
  thirst, from 0 to 5) and Humanity (from 0 to 10).
  """
  def seed_trackers(story) do
    Helpers.seed_trackers(story, [
      %{
        name: "Health",
        slug: "health",
        max_formula: "stamina + 3",
        damage_types: ["superficial", "aggravated"],
        public: true
      },
      %{
        name: "Willpower",
        slug: "willpower",
        max_formula: "composure + resolve",
        damage_types: ["superficial", "aggravated"]
      },
      %{name: "Hunger", slug: "hunger", max_formula: "5", starts_full: false},
      %{name: "Humanity", slug: "humanity", max_formula: "10"}
    ])
  end

  @doc """
  A d10 success pool (6+, a pair of 10s adds two successes): Hunger turns dice
  into Hunger dice (messy criticals and bestial failures), and Willpower is
  spent, as superficial damage, to reroll up to three failed dice.
  """
  def seed_dice(story) do
    Helpers.seed_dice(story, %{
      system: "pool",
      die_size: 10,
      success_threshold: 6,
      crit_rule: "pairs",
      crit_bonus: 2,
      special_tracker: "hunger",
      messy_crit: true,
      bestial_failure: true,
      reroll_tracker: "willpower",
      reroll_cost: 1,
      reroll_damage_type: "superficial",
      reroll_max_dice: 3
    })
  end

  @doc """
  Periodic actions: hunting, feeding from the herd, visiting a Touchstone and
  covering up a breach of the Masquerade.
  """
  def seed_actions(story) do
    Helpers.seed_actions(story, [
      %{
        name: "Hunt",
        description:
          "Go out into the city and find a vessel. The more cameras and cops around, the " <>
            "harder it is to feed unseen.",
        items: ["wits", "streetwise"],
        difficulty_source: "zone",
        zone_property: "heat",
        default_difficulty: 2,
        success_tracker: "hunger",
        success_delta: -2,
        cooldown_hours: 24
      },
      %{
        name: "Feed from your herd",
        description:
          "Visit the people who let you drink, knowingly or not. Safe and familiar, but it " <>
            "never fully quiets the Beast.",
        items: ["charisma", "persuasion"],
        difficulty_source: "character",
        default_difficulty: 2,
        success_tracker: "hunger",
        success_delta: -1,
        cooldown_hours: 24
      },
      %{
        name: "Visit your Touchstone",
        description:
          "Spend an hour near the mortal who reminds you what you were: watch them from " <>
            "across the street, or sit with them, if you dare.",
        items: ["composure", "insight"],
        difficulty_source: "character",
        default_difficulty: 2,
        success_tracker: "willpower",
        success_damage_type: "superficial",
        success_delta: -2,
        cooldown_hours: 24
      },
      %{
        name: "Cover a breach",
        description:
          "Someone filmed something they should not have. Find the phone, the witness and " <>
            "the story before it spreads.",
        items: ["manipulation", "subterfuge"],
        difficulty_source: "zone",
        zone_property: "heat",
        default_difficulty: 3,
        failure_tracker: "health",
        failure_damage_type: "superficial",
        failure_delta: 1,
        cooldown_hours: 24
      }
    ])
  end

  ## Items

  def seed_items(story) do
    if Items.list_items(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :items, true)
      slugs = Sheet.slugs(story)
      trackers = Map.new(Trackers.list_trackers(story), &{&1.slug, &1})

      items = [
        %{
          name: "Bag of O-negative",
          category: "Blood",
          price: 60,
          tracker_id: trackers["hunger"] && trackers["hunger"].id,
          effect_change: -1,
          description:
            "Cold, stolen from a hospital fridge and tasting of plastic. It takes the edge " <>
              "off the Hunger, a little."
        },
        %{
          name: "Ashwood stake",
          category: "Weapons",
          price: 25,
          stackable: false,
          slot: "weapon",
          modifiers: Map.take(%{"melee" => 1}, slugs),
          description:
            "Hand-turned and fire-hardened. Every Kindred in the city hopes you carry it for " <>
              "somebody else."
        },
        %{
          name: "Compact pistol",
          category: "Weapons",
          price: 90,
          stackable: false,
          slot: "weapon",
          modifiers: Map.take(%{"firearms" => 1}, slugs),
          description: "Small, quiet and illegal. It slows Kindred down; it does not stop them."
        },
        %{
          name: "Burner phone",
          category: "Gear",
          price: 15,
          stackable: false,
          slot: "pocket",
          modifiers: Map.take(%{"subterfuge" => 1}, slugs),
          description:
            "Prepaid, untraceable and dropped in the lake once a week. The Masquerade loves you."
        },
        %{
          name: "Silk mourning veil",
          category: "Clothing",
          price: 120,
          stackable: false,
          slot: "head",
          modifiers: Map.take(%{"etiquette" => 1}, slugs),
          description:
            "Black lace in the old style. At Elysium, it says you know the rules and intend " <>
              "to bend them."
        },
        %{
          name: "Mortician's wax",
          category: "Medical",
          price: 20,
          tracker_id: trackers["health"] && trackers["health"].id,
          effect_change: -1,
          effect_damage_type: "superficial",
          description: "Hides the bite, the bruise and the bullet hole long enough to get home."
        }
      ]

      created =
        Map.new(items, fn attrs ->
          {:ok, item} = Items.create_item(story, attrs)
          {item.name, item}
        end)

      market = Enum.find(Stories.list_locations(story), &(&1.name == "Kensington Market"))

      {:ok, shop} =
        Items.create_shop(story, %{
          name: "Mrs. Okafor's Night Pharmacy",
          location_id: market && market.id,
          description:
            "A pharmacy above a cheese shop, open from midnight until the first streetcar. " <>
              "Mrs. Okafor is ghoul to nobody and sells to everybody, as long as you pay in cash."
        })

      [
        {"Bag of O-negative", %{stock: 10}},
        {"Ashwood stake", %{stock: 6}},
        {"Compact pistol", %{stock: 2, price: 110}},
        {"Burner phone", %{stock: 25}},
        {"Silk mourning veil", %{stock: 3}},
        {"Mortician's wax", %{stock: 15}}
      ]
      |> Enum.with_index()
      |> Enum.each(fn {{name, attrs}, index} ->
        {:ok, _} =
          Items.create_listing(
            story,
            shop,
            Map.merge(attrs, %{item_id: created[name].id, position: index})
          )
      end)

      story
    else
      story
    end
  end

  ## Guilds

  def seed_guilds(story) do
    if Guilds.list_guilds(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :guilds, true)

      {:ok, court} =
        Guilds.create_guild(story, %{
          name: "Camarilla Court of Toronto",
          description:
            "The Prince's court: the Primogen, the Sheriff, the Keeper of Elysium and every " <>
              "Kindred who wants protection, status and a hunting ground downtown. " <>
              "**Present yourself to the Prince before you hunt in her Domain.**",
          open_join: true,
          position: 0
        })

      seed_ranks(court, [{"Neonate", 20, false}, {"Ancilla", 40, false}, {"Primogen", 80, true}])

      {:ok, anarchs} =
        Guilds.create_guild(story, %{
          name: "Free Streets Anarchs",
          description:
            "The Barons and gangs of Kensington, Queen West and the east end. No Prince, no " <>
              "bowing: you keep your turf if you can hold it. *Respect the Barons.*",
          open_join: true,
          position: 1
        })

      seed_ranks(anarchs, [{"Rabble", 15, false}, {"Firebrand", 30, false}, {"Baron", 60, true}])

      {:ok, exchange} =
        Guilds.create_guild(story, %{
          name: "The Undercity Exchange",
          description:
            "Information brokers in the tunnels under the PATH. They sell secrets to the " <>
              "Court and the Anarchs alike. *You don't find the Exchange: it finds you.*",
          secret: true,
          open_join: false,
          position: 2
        })

      seed_ranks(exchange, [{"Runner", 10, false}, {"Broker", 30, false}, {"Archivist", 50, true}])

      if is_nil(Repo.get_by(Section, story_id: story.id, name: "The Ledger")) do
        {:ok, _} =
          Forum.create_section(story, %{
            name: "The Ledger",
            description: "Secrets for sale, debts owed and who owes them.",
            visibility: "guild",
            guild_id: exchange.id,
            position: 10
          })
      end

      if is_nil(Repo.get_by(Location, story_id: story.id, name: "The Exchange, PATH Junction 13")) do
        {:ok, _} =
          Stories.create_location(story, %{
            name: "The Exchange, PATH Junction 13",
            description:
              "A sealed-off junction of the underground walkway, behind a door marked " <>
                "SERVICE. Filing cabinets, old CRT screens and Old Ezra's chair.",
            area: "330,200 410,200 410,280 330,280",
            color: "#7f9a8a",
            guild_id: exchange.id
          })
      end

      Stories.get_story!(story.id)
    else
      story
    end
  end

  defp seed_ranks(guild, ranks) do
    for {{name, salary, leader}, position} <- Enum.with_index(ranks) do
      {:ok, _} =
        Guilds.create_rank(guild, %{
          name: name,
          salary: salary,
          leader: leader,
          position: position
        })
    end
  end

  ## Chat roleplay and automatic XP

  def seed_chat_rp(story) do
    if Stories.module_enabled?(story, :chat_rp) or Stories.module_enabled?(story, :auto_xp) do
      story
    else
      {:ok, story} = Stories.set_module_enabled(story, :chat_rp, true)
      {:ok, story} = Stories.set_module_enabled(story, :auto_xp, true)

      {:ok, story} =
        Stories.update_story(story, %{
          chat_min_length: 0,
          chat_max_length: 2000,
          auto_xp_amount: 1,
          auto_xp_min_length: 300,
          auto_xp_daily_cap: 10,
          auto_xp_cooldown_minutes: 10
        })

      story
    end
  end

  ## NPCs

  @doc """
  The named NPCs of Toronto, with their original portraits (static SVGs in
  `priv/static/images/gdr/toronto-by-night/`).
  """
  def npcs do
    [
      %{
        name: "Adelaide Rourke",
        avatar: "adelaide-rourke.svg",
        description:
          "**Prince of Toronto**, Ventrue. Embraced in 1867, the year of Confederation, " <>
            "and she has run the city like a company ever since: pearls, navy wool, a " <>
            "quarterly report for every Primogen. She never raises her voice."
      },
      %{
        name: "Inês Carvalho",
        avatar: "ines-carvalho.svg",
        description:
          "**Baron of the Free Streets**, Brujah. A union organiser from Little Portugal, " <>
            "Embraced on a picket line in 1979. A scar across one eye, a red bandana and a " <>
            "standing offer: help anyone who stands up to the Prince."
      },
      %{
        name: @sample_npc,
        avatar: "celeste-marchand.svg",
        description:
          "**Keeper of Elysium**, Toreador. A Montréal soprano who came west in 1931 and " <>
            "opened the Gilded Hour. She decides who is welcome at Elysium, and who is " <>
            "*remembered* there."
      },
      %{
        name: "Rue Halloran",
        avatar: "rue-halloran.svg",
        description:
          "Caitiff neonate, Embraced last winter and left in a Kensington alley. A studded " <>
            "jacket, half a head of red hair and the worst luck in the city. Everyone owes " <>
            "Rue a favour, or is about to."
      },
      %{
        name: "Old Ezra",
        avatar: "old-ezra.svg",
        description:
          "**Archivist of the Undercity Exchange**, Nosferatu. He has lived under the city " <>
            "since the first subway tunnels were dug, and sells what he hears there. " <>
            "Polite, patient, and never wrong about the price."
      },
      %{
        name: "Mother Ash",
        avatar: "mother-ash.svg",
        description:
          "Gangrel elder of the Don Valley. Grey-haired, gold-eyed, wrapped in a coat of " <>
            "furs. She keeps the ravines and the Bluffs, and neither the Prince nor the " <>
            "Barons hunt there without her leave."
      }
    ]
  end

  @doc "The public path of an NPC portrait."
  def avatar_path(file), do: "#{@avatar_dir}/#{file}"

  defp seed_npcs(story, admin) do
    now = DateTime.utc_now(:second)

    Map.new(npcs(), fn npc ->
      character =
        Repo.get_by(Character, story_id: story.id, name: npc.name) ||
          Repo.insert!(%Character{
            story_id: story.id,
            user_id: admin.id,
            name: npc.name,
            description: npc.description,
            avatar_path: avatar_path(npc.avatar),
            is_npc: true,
            approval_status: "approved",
            reviewed_by_id: admin.id,
            reviewed_at: now
          })

      {npc.name, character}
    end)
  end

  ## Esiti and quests

  def seed_esiti_and_quests(story, admin) do
    if Repo.exists?(from e in Esito, where: e.story_id == ^story.id and e.title == @sample_esito) do
      story
    else
      {:ok, story} = Stories.set_module_enabled(story, :esiti, true)
      {:ok, story} = Stories.set_module_enabled(story, :quests, true)
      npcs = seed_npcs(story, admin)
      npc = npcs[@sample_npc]
      islands = Repo.get_by(Location, story_id: story.id, name: "Toronto Islands")
      seed_sample_esito(story, admin, npc, islands)
      seed_sample_quest(story, admin, npcs, islands)
      Stories.get_story!(story.id)
    end
  end

  defp seed_sample_esito(story, admin, npc, islands) do
    now = DateTime.utc_now(:second)

    esito =
      Repo.insert!(%Esito{
        story_id: story.id,
        character_id: npc.id,
        user_id: admin.id,
        title: @sample_esito,
        body:
          "At four in the morning, long after the last ferry, the old *Trillium* crossed " <>
            "the harbour with its lights off and docked at Ward's Island. Céleste was on " <>
            "the pier, waiting for a guest who never comes late. **Who was on board?**",
        location_id: islands && islands.id,
        status: "resolved",
        claimed_by_id: admin.id,
        claimed_at: now,
        resolved_by_id: admin.id,
        resolved_at: now,
        outcome:
          "Nobody walked off the ferry. In the empty cabin: a wet coat, a cold cup of " <>
            "coffee and an invitation to Elysium, addressed to a Kindred who met the sun " <>
            "in 1998. The handwriting is the Prince's."
      })

    Repo.insert!(%Message{
      esito_id: esito.id,
      user_id: admin.id,
      from_masters: true,
      author_name: "The masters",
      body: "Roll Wits + Awareness to spot what is wrong on the deck before you step aboard."
    })
  end

  defp seed_sample_quest(story, admin, npcs, islands) do
    if is_nil(Repo.get_by(Quest, story_id: story.id, title: @sample_quest)) do
      {:ok, quest} =
        Quests.create_quest(admin, story, %{
          "title" => @sample_quest,
          "summary" =>
            "Three Kindred burned to ash on the Islands' beach in a single week, and the sun " <>
              "never touched them. The Court and the Free Streets called a truce long enough " <>
              "to find out why, and **found the hunter's camp before it found them**.",
          "held_on" => Date.to_iso8601(Date.utc_today()),
          "visibility" => "public",
          "location_id" => islands && islands.id
        })

      for {name, money, note} <- [
            {@sample_npc, "80", "Hosted the truce at Elysium and kept it civil."},
            {"Rue Halloran", "40", "Found the camp, and lived to tell it."}
          ],
          npc = npcs[name] do
        {:ok, _} =
          Quests.add_participant(admin, story, quest, %{
            "character_id" => npc.id,
            "money" => money,
            "note" => note
          })
      end

      {:ok, _} = Quests.apply_rewards(admin, story, Quests.get_quest(story, quest.id))
    end
  end

  ## Diary and boards

  @sheet_template """
  ## Before the Embrace
  Who were you in life? What did you do in Toronto, and who did you leave behind?

  ## The Embrace
  Who is your Sire, why did they choose you, and did they stay?

  ## Touchstones and Convictions
  Who is the mortal that keeps you human, and what will you never do, even to survive?
  """

  def seed_diary_and_boards(story, admin) do
    if Repo.exists?(
         from a in Announcement,
           where: a.story_id == ^story.id and a.title == @sample_announcement
       ) do
      story
    else
      {:ok, story} = Stories.set_module_enabled(story, :diary, true)
      {:ok, story} = Stories.set_module_enabled(story, :boards, true)

      story =
        if is_nil(story.sheet_template) do
          story |> Ecto.Changeset.change(sheet_template: @sheet_template) |> Repo.update!()
        else
          story
        end

      Repo.insert!(%Announcement{
        story_id: story.id,
        user_id: admin.id,
        title: @sample_announcement,
        pinned: true,
        body:
          "The city never sleeps, and neither do you, until dawn. Read the *Guide* (start " <>
            "from **The Masquerade and the Traditions**), choose your clan and present " <>
            "yourself at **Elysium: The Gilded Hour**.\n\n" <>
            "The Elysium noticeboard takes in-character notices: leave yours."
      })

      seed_sample_board(story, admin)
      Stories.get_story!(story.id)
    end
  end

  defp seed_sample_board(story, admin) do
    zone = Repo.get_by(Zones.Zone, story_id: story.id, name: "The Downtown Domain")
    room = Repo.get_by(Location, story_id: story.id, name: "Elysium: The Gilded Hour")
    npc = Repo.get_by(Character, story_id: story.id, name: @sample_npc)

    if zone || room do
      board =
        Repo.insert!(%Board{
          story_id: story.id,
          name: "Elysium noticeboard",
          description:
            "A gilt-framed corkboard in the cloakroom of the Gilded Hour. Notices in ink only.",
          zone_id: zone && zone.id,
          location_id: if(zone, do: nil, else: room.id)
        })

      if npc do
        Repo.insert!(%Notice{
          board_id: board.id,
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "Elysium is open",
          body:
            "Elysium sits every Friday from midnight until four. *No violence, no feeding, " <>
              "no Disciplines.* Newcomers present themselves to the Keeper before the Prince."
        })

        Repo.insert!(%Entry{
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "Ninety-five winters",
          game_date_label: "The first frost of 2026",
          visibility: "public",
          body:
            "Ninety-five winters in this city. I have watched Toronto tear itself down and " <>
              "rebuild itself taller every decade, and every decade it forgets more of us. " <>
              "Tonight a neonate asked me what I miss. **The sun on the lake**, I said, and " <>
              "for one dreadful second I meant it."
        })
      end
    end
  end

  ## Calendar and weather

  @calendar_months """
  January | 31 | Winter
  February | 28 | Winter
  March | 31 | Spring
  April | 30 | Spring
  May | 31 | Spring
  June | 30 | Summer
  July | 31 | Summer
  August | 31 | Summer
  September | 30 | Autumn
  October | 31 | Autumn
  November | 30 | Autumn
  December | 31 | Winter
  """

  @weather_table [
    {"Clear, cold night", "hero-moon",
     "A clear sky over the towers and a moon bright enough to cast shadows. Sound carries.",
     %{
       "Winter" => {30, -15, -6},
       "Spring" => {30, 0, 8},
       "Summer" => {35, 15, 22},
       "Autumn" => {30, 2, 10}
     }},
    {"Lake-effect snow", "hero-cloud",
     "Snow blown off Lake Ontario in thick, sideways bands. Streetcars crawl; footprints " <>
       "vanish in minutes.",
     %{
       "Winter" => {35, -10, -3},
       "Spring" => {5, -3, 1},
       "Summer" => {0, 0, 0},
       "Autumn" => {10, -4, 1}
     }},
    {"Freezing drizzle", "hero-cloud-arrow-down",
     "Fine rain that freezes on contact. Every sidewalk is a sheet of glass.",
     %{
       "Winter" => {20, -6, 0},
       "Spring" => {15, -2, 3},
       "Summer" => {0, 0, 0},
       "Autumn" => {15, -2, 3}
     }},
    {"Fog off the lake", "hero-eye-slash",
     "A thick fog rolls up from the harbour and swallows the CN Tower to its waist. " <>
       "Perfect hunting weather.",
     %{
       "Winter" => {10, -3, 2},
       "Spring" => {30, 4, 11},
       "Summer" => {20, 14, 20},
       "Autumn" => {30, 5, 12}
     }},
    {"Thick, humid night", "hero-bolt",
     "Heat that never breaks after sunset, thunder far over the lake, and the whole city " <>
       "out on its patios. The herd is everywhere.",
     %{
       "Winter" => {5, -2, 3},
       "Spring" => {20, 12, 20},
       "Summer" => {45, 20, 29},
       "Autumn" => {15, 12, 20}
     }}
  ]

  def seed_calendar_and_weather(story) do
    if Calendars.get_calendar(story) do
      story
    else
      {:ok, story} = Stories.set_module_enabled(story, :calendar, true)
      {:ok, story} = Stories.set_module_enabled(story, :weather, true)
      now = DateTime.utc_now()

      {:ok, _} =
        Calendars.save_calendar(story, %{
          "months_text" => @calendar_months,
          "weekdays_text" => "Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday",
          "ratio" => 1,
          "epoch_year" => 2026,
          "epoch_month" => now.month,
          "epoch_day" => min(now.day, 28),
          "epoch_hour" => now.hour,
          "epoch_minute" => now.minute
        })

      for {name, icon, description, seasons} <- @weather_table do
        {:ok, _} =
          Weather.create_condition(story, %{
            name: name,
            icon: icon,
            description: description,
            weights: Map.new(seasons, fn {season, {weight, _, _}} -> {season, weight} end),
            temp_min: Map.new(seasons, fn {season, {_, min, _}} -> {season, min} end),
            temp_max: Map.new(seasons, fn {season, {_, _, max}} -> {season, max} end)
          })
      end

      Weather.roll_story_due(story)
      Stories.get_story!(story.id)
    end
  end

  ## Reports and portal

  def seed_reports(story) do
    if Map.has_key?(story.modules || %{}, "reports") do
      story
    else
      {:ok, story} = Stories.set_module_enabled(story, :reports, true)
      story
    end
  end

  def seed_listing(story) do
    if story.pitch in [nil, ""] do
      {:ok, story} =
        Stories.update_story(story, %{
          genres: ["horror", "urban_fantasy", "modern"],
          lifecycle: "open",
          content_rating: "16",
          pitch:
            "Toronto, 2026: glass towers, cold lake, warm blood. Hunt, scheme and hold on " <>
              "to your Humanity among the Kindred of the city."
        })

      story
    else
      story
    end
  end

  ## Lore

  defp summary do
    "Toronto, 2026. Under the glass towers and the CN Tower's red beacon, the Kindred play " <>
      "their long game: a Ventrue Prince who runs the city like a bank, Anarch Barons who " <>
      "hold the west end, and in the ravines and tunnels, older things that answer to " <>
      "neither. The Masquerade holds, for now."
  end

  defp world_background do
    """
    **Toronto, Ontario, 2026.** Four million people, a forest of cranes and a lake that freezes at its edges every winter. It is a polite city, a careful city, a city that does not ask questions. That is why the Kindred love it.

    For a century and a half Toronto has belonged to **Prince Adelaide Rourke**, a Ventrue who arrived with the railway money and never left. She rules from the **Crown Room**, sixty floors above Bay Street, and she rules the way the banks below her do: through debts, quarterly reviews and the quiet threat of being *written off*.

    Not everyone signed the contract. Since the 1970s, the **Free Streets** (Kensington, Queen West and the old east end) have answered to Anarch **Barons** instead. **Inês Carvalho**, the loudest of them, has turned a union hall into a fortress. The two sides keep a cold peace at **Elysium**, a supper club in Yorkville called the **Gilded Hour**, where the Toreador **Céleste Marchand** keeps the rules.

    Below the city, the **PATH** (thirty kilometres of underground walkways) empties at night. Further down, in tunnels no map shows, the Nosferatu **Old Ezra** runs the **Undercity Exchange** and sells secrets to everyone. Out in the **ravines**, the green scars that cut the city in half, the Gangrel **Mother Ash** keeps the wild places and their old bargains.

    And this winter, something is burning Kindred to ash on the shores of the **Toronto Islands**, without any sun.
    """
  end

  defp traditions do
    """
    > *The night is ours only as long as the day does not know about it.*

    **The Masquerade** is the first law of the Kindred: mortals must never learn that vampires exist. Every phone is a camera and every camera is connected; one viral video could bring the hunters, the governments and the fire. Breaking the Masquerade is the one crime that both the Court and the Anarchs punish.

    The Camarilla of Toronto keeps **six Traditions**, which the Prince enforces through her Sheriff:

    1. **The Masquerade.** Never reveal your nature to those not of the Blood.
    2. **The Domain.** The Prince's city is hers. Present yourself when you arrive, and hunt only where you are allowed.
    3. **The Progeny.** Embrace no one without the Prince's leave.
    4. **The Accounting.** You answer for those you Embrace, until they are released.
    5. **Hospitality.** Honour one another's havens and domains.
    6. **Destruction.** Only the Prince may order the Final Death of another Kindred.

    The Anarchs of the Free Streets keep the Masquerade too; they argue about the rest. In the Free Streets your Baron, not the Prince, decides who may hunt, Embrace and stay.
    """
  end

  defp hunger do
    """
    **Hunger** is the thirst of the Beast, from 0 (sated) to 5 (starving). Every vampire wakes up a little hungrier, and using the Blood makes it worse.

    - Every point of Hunger turns one die of your pool into a **Hunger die**. Use the special dice of your character's dice roller.
    - A **messy critical** is a critical win with a 10 on a Hunger die: you succeed, but the Beast takes over the method. Blood on the walls, a broken arm, a witness.
    - A **bestial failure** is a failure with a 1 on a Hunger die: the Beast lashes out, flees or sulks. The masters decide which.
    - At Hunger 5 you cannot simply feed and stop. Roll to resist a frenzy.

    Lower your Hunger by **hunting** (harder where the zone's *Heat* is high) or by **feeding from your herd**. Blood bags from Mrs. Okafor's pharmacy help, a little.

    **Humanity** (0 to 10) is what is left of the person you were. Every atrocity costs you. Visiting your **Touchstone**, the mortal who anchors you, heals superficial Willpower damage; it does not undo what you have done.

    **Willpower** can be spent to reroll up to three failed regular dice. Each reroll costs one point of superficial Willpower damage.
    """
  end

  defp factions do
    """
    **The Camarilla Court of Toronto.** The Prince, her Primogen council (one elder for each major clan in the city), her Sheriff and her Keeper of Elysium. Downtown, from Yorkville to the lake, is the Prince's **Domain**: safe hunting, cameras everywhere, and the Sheriff's people watching them. Join to gain status and protection, and to owe it.

    **The Free Streets Anarchs.** The Barons of the west end and the east end, who refuse to kneel. Every Baron keeps their own turf and their own rules; together they hold enough of the city that the Prince negotiates instead of burning them out. Join to be free, and to fight for it.

    **The Undercity Exchange.** *Secret.* Information brokers in the tunnels under the PATH, run by Old Ezra. They sell to both sides and belong to neither. Nobody joins the Exchange: one night, it finds you.

    **Independents.** The Gangrel of the ravines, the Hecata who quietly bought the Necropolis, the Banu Haqim who settle debts for a price. They keep to themselves, until they don't.

    **The Second Inquisition.** Mortal hunters with government budgets and very good software. They do not know how many of you there are. Keep it that way.
    """
  end

  defp rules do
    """
    Toronto by Night is a modern gothic-punk role play of vampires, politics and the struggle to stay human, in the style of *Vampire: The Masquerade* (5th edition). It is an unofficial fan game; all its text and art are original.

    1. Play your character, not yourself. Speak in the rooms of the city through your character.
    2. Attributes go from 1 to 5, skills and Disciplines from 0 to 5. Rolls are pools of ten-sided dice (usually Attribute + Skill): every 6 or more is a success, and every pair of 10s adds two more.
    3. **Hunger** turns dice into Hunger dice: a critical with a Hunger 10 is *messy*, a failure with a Hunger 1 is *bestial*. See **Hunger and the Beast**.
    4. **Willpower** pays for rerolls of up to three failed dice (one point of superficial damage each). **Health** and **Willpower** take *superficial* and *aggravated* damage.
    5. No player may destroy another player's character without their consent. Princes, Barons, elders and the Inquisition belong to the masters.
    6. Keep the tone: dark, personal, political. Horror is welcome; real-world hate and harassment are not. Graphic violence and sexual content stay off-screen.
    7. Earn loonies through your job; wages are paid once a day. Send money to other characters from the bank.
    8. The masters have the final word on any dispute.
    """
  end

  defp customs do
    """
    - Newcomers present themselves at Elysium on their first Friday in the city: first to the Keeper, then to the Prince.
    - At Elysium nobody hunts, fights or uses Disciplines. Breaking that rule is the fastest way to be shown the dawn.
    - Never feed on the TTC. The Prince considers the subway *infrastructure*.
    - In the Free Streets, ask the local Baron before you hunt. A gift of blood or a favour is polite.
    - The ravines belong to Mother Ash. Walk in only by invitation, and walk out before dawn.
    - The Exchange always collects. Never borrow from Old Ezra what you cannot pay back.
    """
  end

  defp glossary do
    """
    - **Kindred**: vampires, as they call themselves. **Kine**: mortals.
    - **The Embrace**: the act of turning a mortal into a vampire. **Sire** and **childe**: the maker and the made.
    - **The Beast**: the predator inside every vampire. **Frenzy**: when it takes over.
    - **Hunger**, **Humanity** and **Willpower**: the thirst, the conscience and the strength to resist both.
    - **Touchstone**: a mortal who anchors a vampire's Humanity.
    - **Elysium**: neutral ground where violence is forbidden. In Toronto, the Gilded Hour.
    - **Domain**: the territory a Prince or Baron claims.
    - **Primogen**: the council of clan elders who advise the Prince.
    - **Ghoul**: a mortal fed on vampire blood, loyal and long-lived.
    - **Herd**: the mortals a vampire feeds on regularly.
    - **Final Death**: the true death of a vampire.
    - **The Second Inquisition**: the mortal agencies that hunt Kindred.
    """
  end

  ## Map

  @doc """
  The rooms (locations) of the GDR. Polygons are convex, in a 1000x700
  coordinate space matching `map_svg/0`; the lake lies to the south.
  """
  def locations do
    [
      %{
        name: "Elysium: The Gilded Hour",
        description:
          "A 1920s supper club in Yorkville: velvet booths, a grand piano and mirrors that " <>
            "do not always reflect everyone. Neutral ground. No violence, no feeding.",
        area: "330,60 480,60 480,170 330,170",
        color: "#e8c46a"
      },
      %{
        name: "The Crown Room",
        description:
          "The sixtieth floor of a Bay Street bank tower, glass on every side. The Prince " <>
            "holds court here, against the lights of the whole city.",
        area: "430,300 560,300 560,400 430,400",
        color: "#9fb4d4"
      },
      %{
        name: "Union Station Undercity",
        description:
          "Below the great hall: service tunnels, sealed platforms and the entrances to the " <>
            "PATH, empty and humming after midnight.",
        area: "420,420 560,420 560,490 420,490",
        color: "#7f9a8a"
      },
      %{
        name: "Kensington Market",
        description:
          "Painted houses, vintage shops and bars that never quite close. Anarch turf, and " <>
            "home to Mrs. Okafor's Night Pharmacy.",
        area: "170,200 300,200 300,310 170,310",
        color: "#e88a5a"
      },
      %{
        name: "Club Vesper",
        description:
          "A Queen West nightclub in an old bank: a crowded dance floor up top, and the " <>
            "vault downstairs for those who know the password.",
        area: "150,330 300,330 300,430 150,430",
        color: "#ec5a6d"
      },
      %{
        name: "Distillery District",
        description:
          "Victorian brick, cobbled lanes and gallery windows, lit with strings of bulbs. " <>
            "Busy enough to hunt in, watched enough to be careful.",
        area: "620,390 730,390 730,480 620,480",
        color: "#c98a5a"
      },
      %{
        name: "The Necropolis",
        description:
          "A Victorian cemetery in Cabbagetown with a chapel of black stone. Its caretakers " <>
            "work only at night now, and they are not all alive.",
        area: "610,150 720,150 720,260 610,260",
        color: "#8a7f9a"
      },
      %{
        name: "Don Valley Ravine",
        description:
          "A deep green ravine cutting the city in two, under the highway's roar. Raccoons, " <>
            "coyotes, and the Gangrel who run with them.",
        area: "750,80 840,80 870,330 770,330",
        color: "#6a8a5a"
      },
      %{
        name: "Toronto Islands",
        description:
          "A chain of parkland islands across the harbour, reached by ferry. By night: empty " <>
            "beaches, a lighthouse, and the best view of the skyline.",
        area: "360,590 600,560 640,620 400,660",
        color: "#7fb0c4"
      },
      %{
        name: "Scarborough Bluffs",
        description:
          "White clay cliffs over the lake at the east edge of the city. The wind never " <>
            "stops, and some nights the cliffs whisper names.",
        area: "880,360 980,340 985,500 890,500",
        color: "#d8d0c0"
      }
    ]
  end

  @doc "Original SVG artwork of Toronto by night (1000x700)."
  def map_svg, do: TannhauserGate.Seeds.MapArtwork.read!("toronto-by-night")
end
