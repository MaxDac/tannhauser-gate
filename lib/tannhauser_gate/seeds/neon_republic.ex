defmodule TannhauserGate.Seeds.NeonRepublic do
  @moduledoc """
  Idempotent seed data for the "Neon Republic" GDR: Halcyon Bay, 2093, a
  free-port megasprawl of lattice riders, corporate combines, orbital clans
  and unlicensed AIs. Seeds its GM owner, map and rooms, forum sections,
  sheet, mechanics and every optional module.

  All lore and artwork here is original and only *inspired* by the classic
  cyberpunk "sprawl" novels; no names, places or text are taken from them.
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

  @story_name "Neon Republic"
  @banner_path "/images/gdr/neon-republic-banner.svg"

  @gm %{
    env: "NR_GM",
    email: "gm@neon.republic",
    username: "neon_gm",
    password: "change-me-neon-republic-2093"
  }

  @sample_npc "Sable Okafor"
  @sample_esito "Tailing the Lacewing courier"
  @sample_quest "The Static Bar data heist"
  @sample_announcement "Welcome to the Neon Republic"

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
              theme: "azure",
              currency_name: "scrip",
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
      %{name: "Off the Grid", description: "Out of character chatter.", position: 0},
      %{
        name: "Lattice Lore",
        description: "Questions and theories about Halcyon Bay and its AIs.",
        position: 1
      },
      %{
        name: "Chop Shop",
        description: "Build, tune and share your characters.",
        position: 2
      }
    ]

    for attrs <- sections, is_nil(Repo.get_by(Section, story_id: story.id, name: attrs.name)) do
      {:ok, _} = Forum.create_section(story, attrs)
    end

    :ok
  end

  ## Sheet and jobs

  @doc "Attributes, skills and implants (powers) of the GDR."
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
      attribute.("Body", "Muscle, stamina and how much chrome your frame can carry."),
      attribute.("Reflex", "Speed, coordination and aim."),
      attribute.("Wits", "Reasoning, memory and pattern-matching."),
      attribute.("Cool", "Nerve under fire, poker face, street credibility."),
      attribute.("Interface", "How cleanly your mind meshes with the Lattice."),
      skill.("Lattice Running", "Riding the Lattice, cracking spikewalls, dodging tracers."),
      skill.("Hardware", "Building, fixing and jury-rigging decks and drones."),
      skill.("Streetwise", "Fixers, rumours and the price of everything on the Floor."),
      skill.("Firearms", "Pistols, smartguns and the occasional flechette rifle."),
      skill.("Blades", "Monoblades, retractable claws and broken bottles."),
      skill.("Negotiation", "Haggling, lying and closing a deal before it closes you."),
      skill.("Medtech", "Patching meat, tuning chrome, reading a neural trace."),
      skill.("Piloting", "Hovercabs, cargo drones and orbital shuttles."),
      power.("Wired Reflexes", "Boosted nerves: you act before the others can blink."),
      power.("Neural Jack", "A socket behind the ear, for a deeper, faster Lattice link."),
      power.("Ghost Read", "Feel the presence of an AI behind a voice, a face, a feed."),
      power.("Dead Man's Luck", "Once in a while, the bullet misses. Don't count on it.")
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
      %{name: "Lattice Runner", description: "Freelance data theft for any fixer.", pay: 110},
      %{name: "Bodyguard", description: "Chrome and muscle for hire on the Floor.", pay: 90},
      %{
        name: "Clinic Orderly",
        description: "Scrub floors and hold patients at Doc Ishida's.",
        pay: 50
      },
      %{name: "Market Trader", description: "Sell salvage from a Drowned Market barge.", pay: 60},
      %{name: "Shuttleport Loader", description: "Haul cargo for the orbital lift.", pay: 45},
      %{name: "Static Bar Barback", description: "Pour drinks and keep your ears open.", pay: 35}
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
        {"Rules", rules()},
        {"Customs", customs()},
        {"Street glossary", glossary()}
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

      {:ok, _} =
        Zones.create_property(story, %{name: "Spikewall", slug: "spikewall", default_value: 3})

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
      {"Combine Heights", "Arcologies and the shuttleport, owned and patrolled by the combines.",
       %{"danger" => 1, "spikewall" => 5}, ["Sendai-Volkov Arcology", "Lacewing Shuttleport"]},
      {"The Floor", "The sprawl at street level: markets, clinics and bars that never close.",
       %{"danger" => 4, "spikewall" => 2},
       [
         "Lattice Parlour",
         "Static Bar",
         "Capsule Stacks",
         "Doc Ishida's Back Room",
         "The Drowned Market",
         "Chrome Alley"
       ]},
      {"High Orbit", "The Valcourt clan's habitat ring, a long, quiet way above the smog.",
       %{"danger" => 2, "spikewall" => 4}, ["Lacewing Promenade"]}
    ]
  end

  ## Origins

  def seed_origins(story) do
    if Origins.list_groups(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :origins, true)
      slugs = Sheet.slugs(story)

      {:ok, group} =
        Origins.create_group(story, %{
          name: "Origin",
          description: "Where the Republic found you.",
          required: true,
          position: 0
        })

      options = [
        %{
          name: "Floor-born",
          bonuses: %{"cool" => 1},
          description:
            "Raised between market barges and capsule stacks. Nobody owns you, " <>
              "which also means nobody will come looking."
        },
        %{
          name: "Combine Wage-slave",
          bonuses: %{"wits" => 1, "cool" => -1},
          description:
            "A corporate childhood, a corporate education and a contract you walked out " <>
              "on. The combine **remembers**."
        },
        %{
          name: "Orbital",
          requires_approval: true,
          bonuses: %{"interface" => 1, "body" => -1},
          description:
            "Born in low gravity on the Lacewing ring: tall, fragile and fluent in " <>
              "Lattice protocols before speech.\n\n*Requires the masters' approval.*"
        },
        %{
          name: "Ridden",
          requires_approval: true,
          bonuses: %{"interface" => 2, "cool" => -1},
          description:
            "A human body shared with an unlicensed AI that hides inside your neural " <>
              "jack. You hear it at night.\n\n*Requires the masters' approval.*"
        }
      ]

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

      story
    else
      story
    end
  end

  ## Mechanics: trackers, dice and periodic actions

  @doc "Health (stun/lethal), Edge (rerolls) and Static (neural feedback)."
  def seed_trackers(story) do
    Helpers.seed_trackers(story, [
      %{
        name: "Health",
        slug: "health",
        max_formula: "body * 2 + 4",
        damage_types: ["stun", "lethal"],
        public: true
      },
      %{name: "Edge", slug: "edge", max_formula: "cool + 2"},
      %{name: "Static", slug: "static", max_formula: "interface + 4", starts_full: false}
    ])
  end

  @doc "A d6 success pool (5+), with Edge spent to reroll failed dice."
  def seed_dice(story) do
    Helpers.seed_dice(story, %{
      system: "pool",
      die_size: 6,
      success_threshold: 5,
      crit_rule: "none",
      reroll_tracker: "edge",
      reroll_cost: 1,
      reroll_max_dice: 3
    })
  end

  @doc "Periodic actions: riding the Lattice and scavenging the market."
  def seed_actions(story) do
    Helpers.seed_actions(story, [
      %{
        name: "Ride the Lattice",
        description:
          "Jack in and go fishing for paydata. The deeper the spikewalls, the " <>
            "louder the static in your skull when they bite.",
        items: ["interface", "lattice_running"],
        difficulty_source: "zone",
        zone_property: "spikewall",
        default_difficulty: 2,
        success_tracker: "static",
        success_delta: -1,
        failure_tracker: "static",
        failure_delta: 2,
        cooldown_hours: 12
      },
      %{
        name: "Scavenge the market",
        description: "Dig through salvage barges for something worth selling.",
        items: ["wits", "streetwise"],
        difficulty_source: "zone",
        zone_property: "danger",
        default_difficulty: 2,
        failure_tracker: "health",
        failure_damage_type: "stun",
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

      items = [
        %{
          name: "Kirin Mk. IV deck",
          category: "Hardware",
          price: 900,
          stackable: false,
          slot: "deck",
          modifiers: Map.take(%{"lattice_running" => 1}, slugs),
          description:
            "A matte-black cyberdeck the size of a paperback, with a cracked case " <>
              "and a lovingly overclocked core."
        },
        %{
          name: "Calm derm",
          category: "Medical",
          price: 30,
          description:
            "A blue dermal patch: slows the heart, steadies the hands, dulls the static."
        },
        %{
          name: "Monoblade",
          category: "Weapons",
          price: 350,
          stackable: false,
          slot: "weapon",
          modifiers: Map.take(%{"blades" => 1}, slugs),
          description: "A one-molecule edge in a lacquered grip. Never test it with your thumb."
        },
        %{
          name: "Chrome lenses",
          category: "Implants",
          price: 600,
          stackable: false,
          slot: "eyes",
          modifiers: Map.take(%{"firearms" => 1}, slugs),
          description: "Mirrored ocular implants with a targeting overlay. Nobody sees you blink."
        }
      ]

      created =
        Map.new(items, fn attrs ->
          {:ok, item} = Items.create_item(story, attrs)
          {item.name, item}
        end)

      market = Enum.find(Stories.list_locations(story), &(&1.name == "The Drowned Market"))

      {:ok, shop} =
        Items.create_shop(story, %{
          name: "Auntie Ruo's barge",
          location_id: market && market.id,
          description:
            "A rusting houseboat stacked with salvaged decks, derms and blades. Auntie " <>
              "Ruo takes scrip, favours and, sometimes, secrets."
        })

      [
        {"Kirin Mk. IV deck", %{stock: 2}},
        {"Calm derm", %{stock: 20}},
        {"Monoblade", %{stock: 3}},
        {"Chrome lenses", %{stock: 1, price: 550}}
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

      {:ok, directorate} =
        Guilds.create_guild(story, %{
          name: "Combine Security Directorate",
          description:
            "The Sendai-Volkov Combine's private army. **Good pay, good chrome, and a " <>
              "non-compete clause written in neurotoxin.**",
          open_join: true,
          position: 0
        })

      seed_ranks(directorate, [
        {"Contractor", 25, false},
        {"Operative", 50, false},
        {"Director", 90, true}
      ])

      {:ok, wires} =
        Guilds.create_guild(story, %{
          name: "The Loose Wires",
          description:
            "A leaderless collective of lattice riders who free stray AIs and sell " <>
              "combine secrets. *If you have to ask, you're not invited.*",
          secret: true,
          open_join: false,
          position: 1
        })

      seed_ranks(wires, [{"Script kid", 0, false}, {"Rider", 15, false}, {"Ghost", 30, true}])

      if is_nil(Repo.get_by(Section, story_id: story.id, name: "The Dead Drop")) do
        {:ok, _} =
          Forum.create_section(story, %{
            name: "The Dead Drop",
            description: "Encrypted chatter between the Loose Wires.",
            visibility: "guild",
            guild_id: wires.id,
            position: 10
          })
      end

      if is_nil(Repo.get_by(Location, story_id: story.id, name: "Directorate Ops Floor")) do
        {:ok, _} =
          Stories.create_location(story, %{
            name: "Directorate Ops Floor",
            description:
              "Wall-to-wall surveillance feeds, synthetic coffee and a tactical map of " <>
                "the Floor. Badges only.",
            area: "640,40 760,40 760,140 640,140",
            color: "#ffb86b",
            guild_id: directorate.id
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
      bar = Repo.get_by(Location, story_id: story.id, name: "Static Bar")
      port = Repo.get_by(Location, story_id: story.id, name: "Lacewing Shuttleport")
      seed_sample_esito(story, admin, npc, port)
      seed_sample_quest(story, admin, npc, bar)
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
            "A fixer with mirrored lenses, a laugh like broken glass and a client in orbit.",
          is_npc: true,
          approval_status: "approved",
          reviewed_by_id: admin.id,
          reviewed_at: DateTime.utc_now(:second)
        })

      npc ->
        npc
    end
  end

  defp seed_sample_esito(story, admin, npc, port) do
    now = DateTime.utc_now(:second)

    esito =
      Repo.insert!(%Esito{
        story_id: story.id,
        character_id: npc.id,
        user_id: admin.id,
        title: @sample_esito,
        body:
          "Sable shadows a courier from the Valcourt clan through the shuttleport " <>
            "crowds. **What is he carrying down the well?**",
        location_id: port && port.id,
        status: "resolved",
        claimed_by_id: admin.id,
        claimed_at: now,
        resolved_by_id: admin.id,
        resolved_at: now,
        outcome:
          "A sealed biochip case, cold to the touch. The courier hands it to a " <>
            "Combine medic in the Capsule Stacks. Sable got a photo of both faces.",
        effects: %{"targets" => [npc.name], "xp" => 0, "money" => 0}
      })

    Repo.insert!(%Message{
      esito_id: esito.id,
      user_id: admin.id,
      from_masters: true,
      author_name: "The masters",
      body: "Roll Cool + Streetwise: the shuttleport cams are everywhere."
    })
  end

  defp seed_sample_quest(story, admin, npc, bar) do
    if is_nil(Repo.get_by(Quest, story_id: story.id, title: @sample_quest)) do
      {:ok, quest} =
        Quests.create_quest(admin, story, %{
          "title" => @sample_quest,
          "summary" =>
            "Someone sold a Combine payroll ledger at the Static Bar, then the bar's " <>
              "Lattice node went dark. The crew rode in after it and **brought the ledger back**.",
          "held_on" => Date.to_iso8601(Date.utc_today()),
          "visibility" => "public",
          "location_id" => bar && bar.id
        })

      {:ok, _} =
        Quests.add_participant(admin, story, quest, %{
          "character_id" => npc.id,
          "money" => "80",
          "note" => "Brokered the sale of the ledger."
        })

      {:ok, _} = Quests.apply_rewards(admin, story, Quests.get_quest(story, quest.id))
    end
  end

  ## Diary and boards

  @sheet_template """
  ## Origins
  Floor, combine or orbit: where did the Republic find you?

  ## Chrome
  What have you replaced, and what did it cost you?

  ## The job
  What job went wrong, and who still wants you for it?
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
          "Halcyon Bay never sleeps and neither does the Lattice. Read the *Guide*, " <>
            "build your character and find a fixer at the **Static Bar**.\n\n" <>
            "The pinboards of the Floor take in-character notices: leave yours."
      })

      seed_sample_board(story, admin)
      Stories.get_story!(story.id)
    end
  end

  defp seed_sample_board(story, admin) do
    zone = Repo.get_by(Zones.Zone, story_id: story.id, name: "The Floor")
    room = Repo.get_by(Location, story_id: story.id, name: "The Drowned Market")
    npc = Repo.get_by(Character, story_id: story.id, name: @sample_npc)

    if zone || room do
      board =
        Repo.insert!(%Board{
          story_id: story.id,
          name: "Market pinboard",
          description: "Hand-written flyers and holo-stickers on a barge's rusted hull.",
          zone_id: zone && zone.id,
          location_id: if(zone, do: nil, else: room.id)
        })

      if npc do
        Repo.insert!(%Notice{
          board_id: board.id,
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "Riders wanted",
          body:
            "Need two clean decks and one steady hand. *Pays in orbit scrip.* Static Bar, late."
        })

        Repo.insert!(%Entry{
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "The cold case",
          game_date_label: "The night the node went dark",
          visibility: "public",
          body:
            "The courier never looked back. People from orbit never do: they think " <>
              "gravity only pulls **down**."
        })
      end
    end
  end

  ## Calendar and weather

  @calendar_months """
  Bootmonth | 31 | Winter
  Coldcache | 28 | Winter
  Thawline | 31 | Spring
  Greenscreen | 30 | Spring
  Bloomlight | 31 | Spring
  Highvolt | 30 | Summer
  Brownout | 31 | Summer
  Overclock | 31 | Summer
  Rustfall | 30 | Autumn
  Darkfiber | 31 | Autumn
  Lowtide | 30 | Autumn
  Rollover | 31 | Winter
  """

  @weather_table [
    {"Chemical fog", "hero-eye-slash",
     "A yellow fog off the bay: the holos glow, the drones fly blind.",
     %{
       "Winter" => {30, 0, 6},
       "Spring" => {25, 9, 15},
       "Summer" => {10, 20, 27},
       "Autumn" => {35, 8, 14}
     }},
    {"Monsoon", "hero-cloud-arrow-down",
     "Warm, heavy rain; the Drowned Market rises on its moorings.",
     %{
       "Winter" => {10, 4, 9},
       "Spring" => {30, 12, 18},
       "Summer" => {35, 24, 30},
       "Autumn" => {25, 12, 18}
     }},
    {"Heat haze", "hero-sun", "The air shimmers over the Floor and the coolant pipes hiss.",
     %{
       "Winter" => {5, 8, 14},
       "Spring" => {15, 18, 24},
       "Summer" => {35, 30, 38},
       "Autumn" => {10, 16, 22}
     }},
    {"Ion storm", "hero-bolt",
     "Solar weather: the Lattice crackles and orbital shuttles are grounded.",
     %{
       "Winter" => {15, 1, 7},
       "Spring" => {10, 10, 16},
       "Summer" => {10, 22, 28},
       "Autumn" => {15, 9, 15}
     }},
    {"Grey drizzle", "hero-cloud", "Thin rain from a sky the colour of a blank screen.",
     %{
       "Winter" => {40, 2, 8},
       "Spring" => {20, 10, 15},
       "Summer" => {10, 19, 24},
       "Autumn" => {15, 9, 14}
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
          "weekdays_text" => "Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday",
          "ratio" => 1,
          "epoch_year" => 2093,
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
          genres: ["cyberpunk", "sci_fi"],
          lifecycle: "open",
          content_rating: "16",
          pitch: "Halcyon Bay, 2093: jack in, get paid, and don't let the AIs see you coming."
        })

      story
    else
      story
    end
  end

  ## Lore

  defp summary do
    "Halcyon Bay, 2093. A free port of sixty million souls run by combines, fixers " <>
      "and things that live in the Lattice. Up in orbit, an old family is buying the future."
  end

  defp world_background do
    """
    The **Neon Republic of Halcyon Bay** is a free port: a charter city leased to the highest bidders forty years ago and never given back. Sixty million people live on reclaimed land and floating platforms around a poisoned bay, under a permanent glow of holo-advertising.

    The city is run, in practice, by the **combines**: corporate blocs that own the arcologies, the police contracts and the water. The largest is the Sendai-Volkov Combine, whose black arcology pierces the smog on the north shore. Its security directorate is the closest thing the Republic has to an army.

    Under everything runs the **Lattice**, the global data network. Riders jack in through cyberdecks and neural sockets and see it as a luminous geometry of corporate towers, guarded by *spikewalls*: defensive software that can burn a careless mind. Somewhere in the Lattice live the **strays**, artificial intelligences that slipped their licences. The Leash Authority hunts them; the Loose Wires hide them.

    Above it all, on the **Lacewing** habitat ring, the Valcourt clan has ruled from orbit for three generations. They seldom come down the gravity well, but their couriers do, and lately they have been buying biochips, memories and people.

    At street level lies **the Floor**: capsule hotels, back-room clinics, chrome alleys and the Drowned Market, a flotilla of salvage barges where anything can be bought for scrip, favours or secrets.
    """
  end

  defp rules do
    """
    Neon Republic is a sprawl cyberpunk role play set in Halcyon Bay, 2093.

    1. Play your character, not yourself. Speak in the rooms of the city through your character.
    2. Attributes go from 1 to 5, skills up to 5 and implants up to 3. Rolls are pools of six-sided dice: every 5 or 6 is a success.
    3. **Edge** lets you reroll failed dice; **Static** builds up when the Lattice bites back. Let it fill and your character pays for it.
    4. No player may kill another player's character without their consent. AIs, combines and orbitals belong to the masters.
    5. Keep the tone sharp: high tech, low life, moral grey. Keep it respectful: no real-world hate, no harassment.
    6. Earn scrip through your job; fixers pay once a day. Send scrip to other characters from the bank.
    7. The masters have the final word on any dispute.
    """
  end

  defp customs do
    """
    - Never touch someone's deck without asking. On the Floor, it is worse than touching their face.
    - Mirrored lenses are polite: they tell people you are not reading them. Bare eyes are a challenge.
    - Deals are sealed by swapping a burner chip, never by shaking hands.
    - Orbitals are called "light-boned". To their face, only if you are faster than them.
    - A stray AI that asks for help is never refused, and never mentioned again.
    - Nobody uses real names in the Static Bar, not even the bartender.
    """
  end

  defp glossary do
    """
    - **Lattice**: the global data network, experienced as a luminous space when jacked in.
    - **Rider**: anyone who runs the Lattice for a living. *Script kids* are the amateurs.
    - **Spikewall**: defensive software protecting a node. Black spikewalls can kill.
    - **Stray**: an unlicensed AI. The **Leash Authority** hunts them.
    - **Combine**: a corporate bloc. The Sendai-Volkov Combine is the biggest.
    - **Chrome**: cybernetic implants, from lenses to wired reflexes.
    - **Derm**: a dermal drug patch. *Calm derms* are blue; never trust the black ones.
    - **The well**: the gravity well between the Floor and the Lacewing ring.
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
        name: "Sendai-Volkov Arcology",
        description:
          "A black glass ziggurat on the north shore. Its lobby is a forest of real trees; its upper floors do not exist on any public plan.",
        area: "430,30 570,30 610,180 390,180",
        color: "#4ab8e0"
      },
      %{
        name: "Lattice Parlour",
        description:
          "Rows of rented jack-in couches under blue strip lights. Pay by the hour; the management is not responsible for burnt minds.",
        area: "80,80 250,80 250,210 80,210",
        color: "#86cfe8"
      },
      %{
        name: "Static Bar",
        description:
          "A low bar where the fixers drink. A muted feed of white noise plays on every screen; nobody remembers why.",
        area: "110,280 290,280 290,420 110,420",
        color: "#a8e4f7"
      },
      %{
        name: "Capsule Stacks",
        description:
          "A coffin hotel twelve capsules high. Every pod has a lock, a screen and a reason why its tenant can't go home.",
        area: "350,260 510,260 510,400 350,400",
        color: "#6fd0f0"
      },
      %{
        name: "Doc Ishida's Back Room",
        description:
          "Behind a noodle shop, a spotless surgery. Doc Ishida fits chrome, pulls bullets and forgets faces, for a price.",
        area: "560,260 710,260 710,390 560,390",
        color: "#9be7ff"
      },
      %{
        name: "Chrome Alley",
        description:
          "A narrow street of implant boutiques and knife fights. The neon here is pink, and so is the water in the gutter.",
        area: "770,280 930,280 930,410 770,410",
        color: "#ff7ab8"
      },
      %{
        name: "The Drowned Market",
        description:
          "A flotilla of salvage barges lashed together on the bay. Decks, derms, blades and secrets, all sold by lantern light.",
        area: "200,500 520,500 520,660 200,660",
        color: "#3fb8c8"
      },
      %{
        name: "Lacewing Shuttleport",
        description:
          "The orbital lift terminal: scanners, queues and combine guards. Shuttles climb the well every hour, weather permitting.",
        area: "600,470 800,470 800,630 600,630",
        color: "#c9dbe8"
      },
      %{
        name: "Lacewing Promenade",
        description:
          "The garden ring of the Valcourt habitat, high above the bay. Real grass, real silence, and a view of the whole Republic burning below.",
        area: "800,60 960,60 960,220 800,220",
        color: "#e8f6ff"
      }
    ]
  end

  @doc "Original SVG artwork for Halcyon Bay (1000x700)."
  def map_svg, do: TannhauserGate.Seeds.MapArtwork.read!("neon-republic")
end
