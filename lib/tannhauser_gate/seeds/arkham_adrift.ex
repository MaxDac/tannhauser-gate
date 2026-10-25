defmodule TannhauserGate.Seeds.ArkhamAdrift do
  @moduledoc """
  Idempotent seed data for the "Arkham Adrift" GDR: Arkham, 1923, a New
  England town torn from the world and set adrift in a starless void at the
  edge of a sleeping Old One's dreams. Seeds its GM owner, banner, map and
  rooms, forum sections, sheet, mechanics and every optional module.

  The setting is cosmic horror with a light that does not go out: the parish
  of St. Agnes keeps its lamp burning, the faithful seek the Narrow Gate home
  and Grace (charity, prayer, faith) is a mechanical counterweight to Dread.

  All lore and artwork here is original and only *inspired* by the
  "Stygian: Reign of the Old Ones" video game; it reuses only public domain
  elements of H. P. Lovecraft's fiction (Arkham, the Miskatonic, the Old
  Ones) and public domain (KJV) Scripture.
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
  alias TannhauserGate.Seeds.{Helpers, MapArtwork}
  alias TannhauserGate.Stories.Location

  @story_name "Arkham Adrift"
  @banner_path "/images/gdr/arkham-adrift-banner.svg"

  @gm %{
    env: "AA_GM",
    email: "gm@arkham.adrift",
    username: "arkham_gm",
    password: "change-me-arkham-adrift-1923"
  }

  @sample_npc "Father Thomas Ashby"
  @sample_esito "The bell that rang at midnight"
  @sample_quest "The lost children of Federal Street"
  @sample_announcement "Welcome to Arkham Adrift"

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
              theme: "sepia",
              currency_name: "dollars",
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
      %{name: "The Parlour", description: "Out of character conversation.", position: 0},
      %{
        name: "The Archive",
        description: "Questions and theories about Arkham, the Unmooring and the Narrow Gate.",
        position: 1
      },
      %{
        name: "Character Ledger",
        description: "Build, discuss and share your investigators.",
        position: 2
      }
    ]

    for attrs <- sections, is_nil(Repo.get_by(Section, story_id: story.id, name: attrs.name)) do
      {:ok, _} = Forum.create_section(story, attrs)
    end

    :ok
  end

  ## Sheet and jobs

  @doc "Attributes, skills and gifts (powers) of the GDR."
  def sheet_items do
    attribute = fn name, description ->
      %{kind: "attribute", name: name, description: description, min_value: 1, max_value: 5}
    end

    skill = fn name, description ->
      %{kind: "skill", name: name, description: description, min_value: 0, max_value: 5}
    end

    power = fn name, description ->
      %{kind: "power", name: name, description: description, min_value: 0, max_value: 3}
    end

    [
      attribute.("Brawn", "Strength, stamina and how much punishment your body can take."),
      attribute.("Agility", "Speed, balance and a steady trigger finger."),
      attribute.("Intellect", "Learning, reasoning and memory."),
      attribute.("Perception", "Noticing what others miss, and what is watching you."),
      attribute.("Presence", "Charm, authority and the warmth that makes people trust you."),
      attribute.("Will", "Courage, conviction and the strength to hold on to hope."),
      skill.("Firearms", "Revolvers, shotguns and the rifles brought home from France."),
      skill.("Melee", "Knives, clubs, fists and whatever lies at hand."),
      skill.("Stealth", "Moving unseen through fog-bound streets."),
      skill.("Lockpicking", "Locks, safes and the occasional sealed crypt."),
      skill.("Medicine", "Setting bones, stitching wounds and calming a broken mind."),
      skill.("Occultism", "Forbidden lore. Useful, and never without a price."),
      skill.("Science", "Chemistry, physics and the reassuring order of the natural world."),
      skill.("Persuasion", "Talking, bargaining, comforting and lying."),
      skill.(
        "Scrounging",
        "Finding food, fuel and ammunition in a town running out of all three."
      ),
      skill.("Theology", "Scripture, liturgy and the long wisdom of the Church."),
      power.(
        "Prayer of Warding",
        "A prayer spoken in faith: the things of the void hesitate before it."
      ),
      power.("Second Sight", "Glimpses of what hides behind the fog, and behind faces."),
      power.("Dream Walking", "Walking, eyes closed, in the shallows of the Dreamer's dreams."),
      power.("Elder Sign", "An ancient warding sigil, drawn in chalk, blood or ash.")
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

  @doc "Jobs and their pay (per pay interval)."
  def jobs do
    [
      %{
        name: "Bread-line Volunteer",
        description: "Bake and serve at the St. Agnes soup kitchen. Pays little, feeds many.",
        pay: 20
      },
      %{name: "Scavenger", description: "Comb the abandoned houses for food and fuel.", pay: 45},
      %{name: "Speakeasy Bouncer", description: "Keep the peace at the Lantern.", pay: 60},
      %{
        name: "Sanitarium Orderly",
        description: "Night shifts among those the Unmooring broke.",
        pay: 50
      },
      %{
        name: "Library Archivist",
        description: "Catalogue, guard and sometimes burn the Miskatonic's books.",
        pay: 55
      },
      %{name: "Dockhand", description: "Haul crates and nets on the black river.", pay: 40}
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
      {:ok, world} = Guide.create_section(story, %{title: "The world", position: 0})

      [
        {"Background", world_background()},
        {"Hope and the Narrow Gate", hope()},
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
      {:ok, _} =
        Zones.create_property(story, %{name: "Danger", slug: "danger", default_value: 2})

      {:ok, _} = Zones.create_property(story, %{name: "Veil", slug: "veil", default_value: 3})

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
      {"The Lit Ward",
       "The streets within sight of St. Agnes' lamp. The fog thins here, and so do the nightmares.",
       %{"danger" => 1, "veil" => 1},
       ["St. Agnes' Church", "Independence Square", "The Lantern Speakeasy"]},
      {"Old Town",
       "Gambrel roofs, the university and the river. Mostly safe by day; nobody trusts the night.",
       %{"danger" => 3, "veil" => 3},
       ["Miskatonic University Library", "Riverside Docks", "Arkham Sanitarium"]},
      {"The Fringe",
       "Where the streets thin out and end in cliffs over the void. The veil here is paper-thin.",
       %{"danger" => 5, "veil" => 5}, ["Old Hill Cemetery", "The Fog Edge", "The Hollow Lodge"]}
    ]
  end

  ## Origins

  def seed_origins(story) do
    if Origins.list_groups(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :origins, true)
      slugs = Sheet.slugs(story)

      {:ok, archetype} =
        Origins.create_group(story, %{
          name: "Archetype",
          description: "Who you were before the Unmooring.",
          required: true,
          position: 0
        })

      seed_options(story, archetype, slugs, [
        %{
          name: "Veteran",
          bonuses: %{"brawn" => 1, "firearms" => 1},
          description:
            "You came home from the trenches of France believing you had seen the worst of " <>
              "the world. You were wrong, but you know how to hold a line."
        },
        %{
          name: "Private Eye",
          bonuses: %{"perception" => 1, "stealth" => 1},
          description:
            "A Boston gumshoe on a missing-person case who arrived in Arkham the day before " <>
              "it vanished. The case is still open."
        },
        %{
          name: "Professor",
          bonuses: %{"intellect" => 1, "science" => 1, "brawn" => -1},
          description:
            "A Miskatonic scholar who knows too much about old books and too little about " <>
              "how to survive without them."
        },
        %{
          name: "Physician",
          bonuses: %{"medicine" => 2, "agility" => -1},
          description:
            "Doctors are the most precious thing in Arkham now. You haven't slept properly " <>
              "since the Unmooring."
        },
        %{
          name: "Bootlegger",
          bonuses: %{"presence" => 1, "scrounging" => 1},
          description:
            "Prohibition made you rich; the Unmooring made your contraband the only liquor " <>
              "left in the world. Everybody owes you something."
        },
        %{
          name: "Occultist",
          requires_approval: true,
          bonuses: %{"occultism" => 2, "will" => -1},
          description:
            "You studied the forbidden long before the stars went out, and some say your " <>
              "circle had a hand in it.\n\n*Requires the masters' approval.*"
        }
      ])

      {:ok, creed} =
        Origins.create_group(story, %{
          name: "Creed",
          description: "What you hold on to in the dark.",
          required: true,
          position: 1
        })

      seed_options(story, creed, slugs, [
        %{
          name: "Faith",
          bonuses: %{"will" => 1, "theology" => 1},
          description:
            "You believe that the God who made the stars has not forgotten Arkham, and that " <>
              "the darkness has not overcome the light. Faith is not the absence of fear: it " <>
              "is walking on through it, and **carrying others** with you."
        },
        %{
          name: "Humanism",
          bonuses: %{"presence" => 1, "medicine" => 1},
          description:
            "Whatever is out there, people are what is worth saving. You put your trust in " <>
              "reason, courage and one another."
        },
        %{
          name: "Esotericism",
          requires_approval: true,
          bonuses: %{"occultism" => 1, "intellect" => 1, "will" => -1},
          description:
            "The Old Ones are a power to understand and, perhaps, to bargain with. You know " <>
              "the risks. You think.\n\n*Requires the masters' approval.*"
        },
        %{
          name: "Nihilism",
          bonuses: %{"will" => 1, "presence" => -1},
          description:
            "Nothing means anything, so nothing can frighten you. It is a cold comfort, and " <>
              "some nights it is not enough."
        }
      ])

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

  ## Mechanics: trackers, dice and periodic actions

  @doc """
  Health (bruised/wounded), Dread (the slow loss of sanity) and Grace (the
  strength faith, charity and prayer give).
  """
  def seed_trackers(story) do
    Helpers.seed_trackers(story, [
      %{
        name: "Health",
        slug: "health",
        max_formula: "brawn * 2 + will",
        damage_types: ["bruised", "wounded"],
        public: true
      },
      %{name: "Dread", slug: "dread", max_formula: "will + 5", starts_full: false},
      %{name: "Grace", slug: "grace", max_formula: "will + theology / 2 + 1"}
    ])
  end

  @doc """
  A d10 success pool (6+): Dread turns dice into dread dice (breakdowns and
  terrible revelations) while Grace is spent to reroll failed dice.
  """
  def seed_dice(story) do
    Helpers.seed_dice(story, %{
      system: "pool",
      die_size: 10,
      success_threshold: 6,
      crit_rule: "pairs",
      crit_bonus: 2,
      special_tracker: "dread",
      messy_crit: true,
      bestial_failure: true,
      reroll_tracker: "grace",
      reroll_cost: 1,
      reroll_max_dice: 3
    })
  end

  @doc """
  Periodic actions: scavenging, keeping vigil, serving the bread line and
  studying forbidden lore.
  """
  def seed_actions(story) do
    Helpers.seed_actions(story, [
      %{
        name: "Scavenge the ruins",
        description:
          "Search the empty houses for food, fuel and cartridges. The further from the " <>
            "lamp, the richer the pickings, and the hungrier what waits inside.",
        items: ["perception", "scrounging"],
        difficulty_source: "zone",
        zone_property: "danger",
        default_difficulty: 2,
        failure_tracker: "health",
        failure_damage_type: "bruised",
        failure_delta: 1,
        cooldown_hours: 24
      },
      %{
        name: "Keep vigil at St. Agnes",
        description:
          "Spend the night in prayer before the sanctuary lamp. In its small, steady light " <>
            "the nightmares loosen their grip.",
        items: ["will", "theology"],
        difficulty_source: "character",
        default_difficulty: 1,
        success_tracker: "dread",
        success_delta: -2,
        cooldown_hours: 24
      },
      %{
        name: "Serve the bread line",
        description:
          "Bake, carry and serve at the parish soup kitchen. Charity feeds the hungry, and " <>
            "it feeds something in you too.",
        items: ["presence", "persuasion"],
        difficulty_source: "character",
        default_difficulty: 1,
        success_tracker: "grace",
        success_delta: 1,
        cooldown_hours: 24
      },
      %{
        name: "Study the forbidden",
        description:
          "Read what should not be read, hoping to find a way home in it. Where the veil " <>
            "is thin, the words read you back.",
        items: ["intellect", "occultism"],
        difficulty_source: "zone",
        zone_property: "veil",
        default_difficulty: 3,
        failure_tracker: "dread",
        failure_delta: 2,
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
          name: ".38 service revolver",
          category: "Weapons",
          price: 40,
          stackable: false,
          slot: "weapon",
          modifiers: Map.take(%{"firearms" => 1}, slugs),
          description:
            "A heavy six-shooter with a lanyard ring, carried home from the war. " <>
              "Cartridges are worth more than dollars now."
        },
        %{
          name: "Trench knife",
          category: "Weapons",
          price: 15,
          stackable: false,
          slot: "weapon",
          modifiers: Map.take(%{"melee" => 1}, slugs),
          description: "A knuckle-duster grip and a triangular blade. Quiet, and always loaded."
        },
        %{
          name: "Medal of St. Agnes",
          category: "Devotional",
          price: 5,
          stackable: false,
          slot: "neck",
          modifiers: Map.take(%{"will" => 1}, slugs),
          description:
            "A worn bronze medal blessed by Father Ashby. It will not stop a claw. It " <>
              "reminds you that you are not alone."
        },
        %{
          name: "Annotated grimoire",
          category: "Books",
          price: 120,
          stackable: false,
          slot: "tome",
          modifiers: Map.take(%{"occultism" => 1}, slugs),
          description:
            "A water-stained book of rites, its margins crowded with a dead man's notes. " <>
              "Some of the notes are *warnings*."
        },
        %{
          name: "Laudanum",
          category: "Medical",
          price: 8,
          tracker_id: trackers["dread"] && trackers["dread"].id,
          effect_change: -1,
          description: "A few bitter drops in water, and the whispering goes quiet for a while."
        },
        %{
          name: "Field dressing",
          category: "Medical",
          price: 5,
          tracker_id: trackers["health"] && trackers["health"].id,
          effect_change: -1,
          effect_damage_type: "bruised",
          description: "Clean linen, iodine and a steady hand."
        }
      ]

      created =
        Map.new(items, fn attrs ->
          {:ok, item} = Items.create_item(story, attrs)
          {item.name, item}
        end)

      square = Enum.find(Stories.list_locations(story), &(&1.name == "Independence Square"))

      {:ok, shop} =
        Items.create_shop(story, %{
          name: "Hester Crane's pawnshop",
          location_id: square && square.id,
          description:
            "A cramped shop of pawned heirlooms, guns and books under a cracked gas lamp. " <>
              "Old Hester takes dollars, bread and, if you insist, your secrets."
        })

      [
        {".38 service revolver", %{stock: 3}},
        {"Trench knife", %{stock: 5}},
        {"Medal of St. Agnes", %{stock: 30}},
        {"Annotated grimoire", %{stock: 1, price: 150}},
        {"Laudanum", %{stock: 12}},
        {"Field dressing", %{stock: 20}}
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

      {:ok, lamplighters} =
        Guilds.create_guild(story, %{
          name: "The Lamplighters of St. Agnes",
          description:
            "A parish brotherhood of every trade and creed that keeps the lamp burning, " <>
              "feeds the hungry, brings the lost back from the fog and searches for the " <>
              "Narrow Gate. **No one who knocks is turned away.**",
          open_join: true,
          position: 0
        })

      seed_ranks(lamplighters, [
        {"Novice", 15, false},
        {"Keeper of the Lamp", 30, false},
        {"Warden of the Lamp", 60, true}
      ])

      {:ok, lodge} =
        Guilds.create_guild(story, %{
          name: "The Black Star Lodge",
          description:
            "A secret society that hails the Old Ones as the true gods and Arkham as their " <>
              "offering. *Membership is by invitation, and the invitation is a dream.*",
          secret: true,
          open_join: false,
          position: 1
        })

      seed_ranks(lodge, [{"Initiate", 0, false}, {"Adept", 20, false}, {"Hierophant", 40, true}])

      if is_nil(Repo.get_by(Section, story_id: story.id, name: "The Inner Circle")) do
        {:ok, _} =
          Forum.create_section(story, %{
            name: "The Inner Circle",
            description: "Whispers between the brothers and sisters of the Black Star.",
            visibility: "guild",
            guild_id: lodge.id,
            position: 10
          })
      end

      if is_nil(Repo.get_by(Location, story_id: story.id, name: "Lamplighters' Vestry")) do
        {:ok, _} =
          Stories.create_location(story, %{
            name: "Lamplighters' Vestry",
            description:
              "A warm back room of the church: lanterns, maps of the fog, a ledger of the " <>
                "missing and a pot of coffee that never quite runs dry.",
            area: "30,90 110,90 110,230 30,230",
            color: "#fff1c4",
            guild_id: lamplighters.id
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

  ## Esiti and quests

  def seed_esiti_and_quests(story, admin) do
    if Repo.exists?(from e in Esito, where: e.story_id == ^story.id and e.title == @sample_esito) do
      story
    else
      {:ok, story} = Stories.set_module_enabled(story, :esiti, true)
      {:ok, story} = Stories.set_module_enabled(story, :quests, true)
      npc = seed_sample_npc(story, admin)
      church = Repo.get_by(Location, story_id: story.id, name: "St. Agnes' Church")
      edge = Repo.get_by(Location, story_id: story.id, name: "The Fog Edge")
      seed_sample_esito(story, admin, npc, church)
      seed_sample_quest(story, admin, npc, edge)
      Stories.get_story!(story.id)
    end
  end

  defp seed_sample_npc(story, admin) do
    case Repo.get_by(Character, story_id: story.id, name: @sample_npc) do
      nil ->
        Repo.insert!(%Character{
          story_id: story.id,
          user_id: admin.id,
          name: @sample_npc,
          description:
            "The parish priest of St. Agnes: grey cassock, a soldier's shoulders, a lantern " <>
              "in one hand and a rosary in the other. He has buried too many and still smiles.",
          is_npc: true,
          approval_status: "approved",
          reviewed_by_id: admin.id,
          reviewed_at: DateTime.utc_now(:second)
        })

      npc ->
        npc
    end
  end

  defp seed_sample_esito(story, admin, npc, church) do
    now = DateTime.utc_now(:second)

    esito =
      Repo.insert!(%Esito{
        story_id: story.id,
        character_id: npc.id,
        user_id: admin.id,
        title: @sample_esito,
        body:
          "At midnight the bell of St. Agnes rang three times, and nobody was in the tower. " <>
            "Father Ashby climbs the stairs with a lantern. **What rang it?**",
        location_id: church && church.id,
        status: "resolved",
        claimed_by_id: admin.id,
        claimed_at: now,
        resolved_by_id: admin.id,
        resolved_at: now,
        outcome:
          "The tower is empty and the dust undisturbed. On the bronze of the bell, freshly " <>
            "engraved as if by a fingertip of light: *\"The gate is narrow, but it is open.\"*",
        effects: %{"targets" => [npc.name], "xp" => 0, "money" => 0}
      })

    Repo.insert!(%Message{
      esito_id: esito.id,
      user_id: admin.id,
      from_masters: true,
      author_name: "The masters",
      body: "Roll Will + Theology: whatever waits up there, the stairs are long and dark."
    })
  end

  defp seed_sample_quest(story, admin, npc, edge) do
    if is_nil(Repo.get_by(Quest, story_id: story.id, title: @sample_quest)) do
      {:ok, quest} =
        Quests.create_quest(admin, story, %{
          "title" => @sample_quest,
          "summary" =>
            "Four children followed a singing voice into the fog. The Lamplighters went " <>
              "after them with lanterns and hymns, held the line at the cliff's edge and " <>
              "**brought every one of them home**.",
          "held_on" => Date.to_iso8601(Date.utc_today()),
          "visibility" => "public",
          "location_id" => edge && edge.id
        })

      {:ok, _} =
        Quests.add_participant(admin, story, quest, %{
          "character_id" => npc.id,
          "money" => "50",
          "note" => "Led the search and kept the lantern lit."
        })

      {:ok, _} = Quests.apply_rewards(admin, story, Quests.get_quest(story, quest.id))
    end
  end

  ## Diary and boards

  @sheet_template """
  ## Origins
  Who were you before the Unmooring, and what were you doing in Arkham that night?

  ## Creed
  What do you hold on to in the dark? What would make you let go?

  ## The way home
  Who are you trying to bring home, and what would you sacrifice for them?
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
          "Arkham is adrift, but it is not forsaken. Read the *Guide* (start from " <>
            "**Hope and the Narrow Gate**), build your investigator and follow the bell " <>
            "to **St. Agnes' Church**.\n\n" <>
            "The church door takes in-character notices: leave yours."
      })

      seed_sample_board(story, admin)
      Stories.get_story!(story.id)
    end
  end

  defp seed_sample_board(story, admin) do
    zone = Repo.get_by(Zones.Zone, story_id: story.id, name: "The Lit Ward")
    room = Repo.get_by(Location, story_id: story.id, name: "St. Agnes' Church")
    npc = Repo.get_by(Character, story_id: story.id, name: @sample_npc)

    if zone || room do
      board =
        Repo.insert!(%Board{
          story_id: story.id,
          name: "The church door",
          description: "Notices nailed to the oak door of St. Agnes, beneath the lamp.",
          zone_id: zone && zone.id,
          location_id: if(zone, do: nil, else: room.id)
        })

      if npc do
        Repo.insert!(%Notice{
          board_id: board.id,
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "Bread at the bell",
          body:
            "Soup and bread every morning at the bell, for anyone. *Hands to bake and " <>
              "carry are always welcome.* Lanterns are lent at the vestry door."
        })

        Repo.insert!(%Entry{
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "The fortieth night",
          game_date_label: "The fortieth night after the Unmooring",
          visibility: "public",
          body:
            "No oil has been poured into the sanctuary lamp for forty nights, and still it " <>
              "burns. *The light shineth in darkness; and the darkness comprehended it not.* " <>
              "Tonight I counted the faces at the bread line: more than yesterday. " <>
              "We are fewer every week, and **we are not alone**."
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
    {"Grey fog", "hero-eye-slash",
     "A thick, grey fog rolls in from the void: lanterns shrink to sparks and voices carry wrong.",
     %{
       "Winter" => {35, -6, 1},
       "Spring" => {35, 2, 9},
       "Summer" => {30, 10, 17},
       "Autumn" => {40, 3, 10}
     }},
    {"Black rain", "hero-cloud-arrow-down",
     "Warm, oily rain that smells of the sea. It stains clothes and fills the gutters with ink.",
     %{
       "Winter" => {15, 0, 5},
       "Spring" => {25, 5, 12},
       "Summer" => {25, 14, 21},
       "Autumn" => {25, 6, 12}
     }},
    {"Void wind", "hero-sparkles",
     "A cold wind from beyond the cliffs, full of faint music. Shutters stay closed.",
     %{
       "Winter" => {25, -12, -4},
       "Spring" => {10, -2, 5},
       "Summer" => {10, 6, 12},
       "Autumn" => {15, -1, 6}
     }},
    {"Ashfall", "hero-fire",
     "Fine grey ash drifts down from a sky with no fire in it. It tastes of old pages.",
     %{
       "Winter" => {10, -4, 2},
       "Spring" => {10, 4, 10},
       "Summer" => {15, 15, 22},
       "Autumn" => {10, 4, 10}
     }},
    {"Pale dawn", "hero-sun",
     "For an hour the fog lifts and a true, clean light falls on Arkham from nowhere. The " <>
       "faithful call it the Promise.",
     %{
       "Winter" => {15, -2, 4},
       "Spring" => {20, 8, 15},
       "Summer" => {20, 17, 25},
       "Autumn" => {10, 7, 14}
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
          "epoch_year" => 1923,
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
          genres: ["horror", "historical", "mystery_noir"],
          lifecycle: "open",
          content_rating: "16",
          pitch:
            "Arkham, 1923: torn from the world and adrift in the void. Keep the lamp lit, " <>
              "keep each other, and find the Narrow Gate home."
        })

      story
    else
      story
    end
  end

  ## Lore

  defp summary do
    "Arkham, 1923. A year ago the town was torn from the world and set adrift in a starless " <>
      "void, at the edge of the dreams of something vast and sleeping. The dead walk, cults " <>
      "pray to the dark, bread runs short, and yet the lamp of St. Agnes has never gone out."
  end

  defp world_background do
    """
    **Arkham, Massachusetts, 1923.** On All Hallows' Eve of last year the bells of the town rang by themselves, the ground shook, and the stars went out. When morning came, it did not come: Arkham woke under a black, starless sky. Its roads now end at cliffs of fog; beyond them there is nothing but a dark sea of void. People call that night **the Unmooring**.

    The town is adrift at the edge of the dreams of the **Dreamer**, one of the Old Ones: a thing so vast and ancient that some of its dreams take flesh. They crawl up the Miskatonic, whisper from the fog and walk, sometimes, in the shapes of the dead of Old Hill.

    Arkham is falling apart. Food and fuel are rationed by whoever has the guns; the bootleggers' liquor is the only currency harder than dollars; the Sanitarium is full and the University's forbidden books are the most stolen objects in town. In the Hollow Lodge, the **Black Star** cult preaches that the Old Ones are the true gods and Arkham their offering, and more people listen every week.

    And yet: the bell of **St. Agnes** still rings at what used to be dawn. The sanctuary lamp before its altar has burned without oil since the Unmooring. Around the church, in the **Lit Ward**, the fog thins and the nightmares lose their grip. The **Lamplighters** go out from there with lanterns and bread, bringing back the lost and searching the edges of the world for a way home.

    Some of them have glimpsed it: a **Narrow Gate** of clean light, far out in the fog.
    """
  end

  defp hope do
    """
    > *And the light shineth in darkness; and the darkness comprehended it not.* (John 1:5)

    **Arkham is adrift, but it is not forsaken.** This is a horror setting, and its horror is real: the Old Ones are vast, ancient and terrible, and they will cost your characters dearly. But this is not a world without hope, and it does not end in despair unless your characters choose despair.

    **The Old Ones are not gods.** The Black Star Lodge worships them; the parish of St. Agnes does not. They are creatures: great, fallen and hungry, but creatures, and they are not the last word. Light still reaches Arkham: the lamp that burns without oil, the bell that rings at dawn, the *Pale Dawn* that sometimes lifts the fog for an hour.

    **The Narrow Gate.** Those who keep faith, and especially those who give themselves for others, sometimes see it in dreams and at the Fog Edge: a narrow gate of light, far out in the void. *"Enter ye in at the strait gate... because strait is the gate, and narrow is the way, which leadeth unto life, and few there be that find it."* (Matthew 7:13-14). Finding the way home is the long road of the campaign.

    **Grace is a mechanic, not only a theme.** Dread drags your dice into madness; Grace lets you reroll them. Grace grows through charity (serve the bread line) and the masters award it for sacrifice, mercy and courage. Keeping vigil before the lamp lowers your Dread.

    **How to play it.** Characters of every creed are welcome, and doubt is part of the story: faith in Arkham is tested, never naive. Play believers, doubters and unbelievers with respect. Despair is a temptation your character may face; it is never the setting's final word.
    """
  end

  defp rules do
    """
    Arkham Adrift is a cosmic horror role play of hope against the dark, set in Arkham, 1923.

    1. Play your character, not yourself. Speak in the rooms of the town through your character.
    2. Attributes go from 1 to 5, skills up to 5 and gifts up to 3. Rolls are pools of ten-sided dice: every 6 or more is a success, and every pair of 10s adds two more.
    3. **Dread** is the slow loss of your sanity: every point turns one die into a dread die. A failure with a dread 1 is a *breakdown*; a critical with a dread 10 is a *terrible revelation*. Keep vigil at St. Agnes to lower it.
    4. **Grace** can be spent to reroll up to three failed dice. Serve the bread line to restore it; the masters award it for sacrifice and mercy.
    5. No player may kill another player's character without their consent. The Old Ones, their dreams and the cults belong to the masters.
    6. Keep the tone: genuine horror, and a light that does not go out. Be respectful of every faith and of every player: no real-world hate, no harassment.
    7. Earn dollars through your job; wages are paid once a day. Send money to other characters from the bank.
    8. The masters have the final word on any dispute.
    """
  end

  defp customs do
    """
    - Doors are bolted at the *false dusk*, when the fog thickens. Whoever knocks after must say a line of Scripture or a nursery rhyme through the keyhole: the things in the fog can do neither.
    - Never put out someone else's lantern. On the Fringe, it is as good as murder.
    - In the Lit Ward bread is not sold at the bell: it is shared.
    - Nobody says the names written in the Lodge's books aloud, not even to mock them.
    - At the Fog Edge, nobody looks down for long.
    - Prohibition still holds, and nobody remembers why it matters. The Lantern's password changes every night.
    """
  end

  defp glossary do
    """
    - **The Unmooring**: the night Arkham was torn from the world, on All Hallows' Eve, 1922.
    - **The Dreamer**: the sleeping Old One at the edge of whose dreams Arkham drifts.
    - **The Fog Edge**: the cliffs where the streets end, over the black void.
    - **The Lit Ward**: the streets within sight of St. Agnes' lamp, where the fog thins.
    - **The Lamp**: the sanctuary lamp of St. Agnes, burning without oil since the Unmooring.
    - **Lamplighters**: the parish brotherhood that keeps the lamp, feeds the town and searches for the way home.
    - **The Narrow Gate**: a gate of light glimpsed far out in the fog. Many believe it leads home.
    - **The Black Star**: the cult that worships the Old Ones, gathered in the Hollow Lodge.
    - **Dread** and **Grace**: what pulls your mind down into the dark, and what lifts it up.
    - **False dusk**: the hour the fog thickens, when good people bolt their doors.
    """
  end

  ## Map

  @doc """
  The rooms (locations) of the GDR. Polygons are convex, in a 1000x700
  coordinate space matching `map_svg/0`.
  """
  def locations do
    [
      %{
        name: "St. Agnes' Church",
        description:
          "A granite church with a tall spire. Its bell still rings at dawn and the lamp before its altar has burned without oil since the Unmooring. The doors are never locked.",
        area: "150,90 300,90 300,240 150,240",
        color: "#f3dc9a"
      },
      %{
        name: "Miskatonic University Library",
        description:
          "Oak stacks, green lamps and a locked reading room of forbidden books, guarded by librarians who no longer sleep.",
        area: "400,40 600,40 600,170 400,170",
        color: "#c9b48a"
      },
      %{
        name: "Independence Square",
        description:
          "The heart of the town: the bread line at the bell, the gallows-shaped bandstand, market stalls trading cartridges for potatoes.",
        area: "360,250 560,250 560,380 360,380",
        color: "#d4a94a"
      },
      %{
        name: "The Lantern Speakeasy",
        description:
          "A cellar bar behind a shuttered barbershop. A jazz trio plays every night, because silence is worse.",
        area: "130,320 290,320 290,450 130,450",
        color: "#e0b86a"
      },
      %{
        name: "Riverside Docks",
        description:
          "Wharves on the black Miskatonic. The fishermen still cast their nets, and sometimes they pull up things with too many eyes.",
        area: "620,330 800,330 800,450 620,450",
        color: "#8fa7a0"
      },
      %{
        name: "Arkham Sanitarium",
        description:
          "A red-brick asylum on a rise, overflowing since the Unmooring. Some patients sing in a language nobody taught them.",
        area: "700,70 880,70 880,210 700,210",
        color: "#a9c98a"
      },
      %{
        name: "Old Hill Cemetery",
        description:
          "Leaning slate headstones on a windy hill. Not every grave is still occupied.",
        area: "850,250 970,250 970,380 850,380",
        color: "#7f9a6a"
      },
      %{
        name: "The Fog Edge",
        description:
          "Where Federal Street ends in a cliff over the void. The Lamplighters keep a lantern burning here, facing outward, for whoever might be coming home.",
        area: "300,560 560,560 600,660 260,660",
        color: "#b8c9a0"
      },
      %{
        name: "The Hollow Lodge",
        description:
          "A boarded-up fraternal lodge with a black star painted over its door. Candles burn behind the shutters on the nights with no moon, which are all of them now.",
        area: "650,500 800,500 800,620 650,620",
        color: "#5f7a45"
      }
    ]
  end

  @doc "Original SVG artwork for Arkham adrift in the void (1000x700)."
  def map_svg, do: MapArtwork.read!("arkham-adrift")
end
