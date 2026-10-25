defmodule TannhauserGate.Seeds do
  @moduledoc """
  Idempotent seed data: the default "Tannhauser Gate" story with its city map
  and rooms, a default admin account and a few forum sections.

  All lore and artwork here is original and only *inspired* by the
  neo-noir/cyberpunk genre.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.{
    Accounts,
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

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Boards.{Announcement, Board, Notice}
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Diary.Entry
  alias TannhauserGate.Esiti.{Esito, Message}
  alias TannhauserGate.Forum.Section
  alias TannhauserGate.Quests.Quest
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
    seed_sections(story)
    seed_sheet(story)
    seed_jobs(story)
    seed_guide(story)
    seed_zones(story)
    story = seed_origins(story)
    story = seed_items(story)
    story = seed_guilds(story)
    story = seed_chat_rp(story)
    story = seed_esiti_and_quests(story, admin)
    story = seed_diary_and_boards(story, admin)
    story = seed_calendar_and_weather(story)
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
              password: password,
              terms_accepted: true
            })

          user

        user ->
          user
      end

    user
    |> User.confirm_changeset()
    |> Repo.update!()
    |> then(fn user ->
      {:ok, user} = Accounts.set_user_flags(user, %{admin: true})
      user
    end)
  end

  ## Story

  def seed_story do
    attrs = %{
      name: @story_name,
      summary: summary(),
      status: "published",
      theme: "tannhauser",
      currency_name: "credits",
      map_svg: map_svg(),
      map_width: 1000,
      map_height: 700,
      is_default: true
    }

    story =
      case Stories.get_story_by_name(@story_name) do
        nil ->
          {:ok, story} = Stories.create_story(attrs)
          story

        story ->
          # The migration may have created a bare placeholder for the old
          # forum: fill in whatever is still blank, never overwrite edits.
          blanks =
            for {key, value} <-
                  Map.take(attrs, [:summary, :map_svg]),
                Map.get(story, key) in [nil, ""],
                into: %{},
                do: {key, value}

          if blanks == %{} do
            story
          else
            {:ok, story} = Stories.update_story(story, blanks)
            story
          end
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

    for attrs <- sections, is_nil(Repo.get_by(Section, story_id: story.id, name: attrs.name)) do
      {:ok, _} = Forum.create_section(story, attrs)
    end

    :ok
  end

  ## Sheet and jobs

  @doc "Attributes, skills and powers of the default story."
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
      attribute.("Body", "Strength, endurance and the ability to take a hit."),
      attribute.("Reflex", "Speed, agility and aim."),
      attribute.("Mind", "Reasoning, memory and focus."),
      attribute.("Empathy", "Reading and moving people, human or Echo."),
      attribute.("Resolve", "Willpower against fear, pain and temptation."),
      skill.("Investigation", "Finding clues and reconstructing a scene."),
      skill.("Streetwise", "Navigating the Undercity and its Gutterline."),
      skill.("Firearms", "Shooting, from sidearms to rain-slicked rooftops."),
      skill.("Hacking", "Breaking into terminals, drones and memory vaults."),
      skill.("Persuasion", "Charm, intimidation and bargaining over noodles."),
      skill.("Piloting", "Spinners, barges and shuttles."),
      skill.("Medicine", "Patching flesh and decoding Echo biology."),
      power.("Echo Memory", "Recall implanted memories as if they were your own."),
      power.("Lumen Sight", "See the telltale iris pattern of an Echo at a glance."),
      power.("Ghost Signal", "Slip unseen through surveillance networks."),
      power.("Warden's Instinct", "A flash of intuition at the moment it matters.")
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

  @doc "Jobs and their pay (per pay interval) in the default story."
  def jobs do
    [
      %{name: "Warden", description: "Hunt illegal Echoes for Precinct 9.", pay: 120},
      %{name: "Noodle Cook", description: "Feed the Undercity at Ozu's counter.", pay: 40},
      %{name: "Memory Artisan", description: "Craft memories at the Lacuna Atelier.", pay: 90},
      %{name: "Bazaar Trader", description: "Buy and sell anything in the Neon Bazaar.", pay: 60},
      %{name: "Spaceport Clerk", description: "Check Lumen scans at Gate 7.", pay: 50}
    ]
  end

  def seed_jobs(story) do
    existing = MapSet.new(Bank.list_jobs(story), & &1.name)

    for attrs <- jobs(), not MapSet.member?(existing, attrs.name) do
      {:ok, _} = Bank.create_job(story, attrs)
    end

    :ok
  end

  ## Origins

  @doc """
  Enables the origins module on the default story and seeds its "Origin"
  group the first time (an admin who later disables the module keeps it off).
  Returns the (possibly updated) story.
  """
  def seed_origins(story) do
    if Origins.list_groups(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :origins, true)

      {:ok, group} =
        Origins.create_group(story, %{
          name: "Origin",
          description: "Born in Neo-Meridian, or grown in a Lumen vat?",
          required: true,
          position: 0
        })

      {:ok, _} =
        Origins.create_option(story, %{
          group_id: group.id,
          name: "Human",
          position: 0,
          description:
            "Flesh, blood and real memories. Humans run the Precincts, the corporations " <>
              "and the noodle stalls of Neo-Meridian, 2121."
        })

      {:ok, _} =
        Origins.create_option(story, %{
          group_id: group.id,
          name: "Replicant",
          position: 1,
          requires_approval: true,
          # Only the items still present in the (editable) sheet.
          bonuses: Map.take(%{"body" => 1, "empathy" => -1}, Sheet.slugs(story)),
          description:
            "An **Echo**: engineered stronger than any human, with implanted memories and an " <>
              "iris pattern Lumen scanners can read. Wardens hunt the illegal ones.\n\n" <>
              "*Requires the masters' approval.*"
        })

      story
    else
      story
    end
  end

  ## Chat roleplay and automatic XP

  @doc """
  Enables the chat roleplay (whispers, action tags, speech highlighting,
  entries up to 2000 characters) and automatic XP (1 XP per in-character
  entry of at least 300 characters, at most 10 a day, every 10 minutes)
  modules. Only the first time: later GM changes are kept.
  """
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

  ## Guilds

  @doc """
  Enables the guilds module with two factions: the Meridian Police
  Department (open to requests) and the secret, invitation-only Echo
  Underground, with a guild forum section and a briefing room reserved to
  the police.
  """
  def seed_guilds(story) do
    if Guilds.list_guilds(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :guilds, true)

      {:ok, police} =
        Guilds.create_guild(story, %{
          name: "Meridian Police Department",
          description:
            "Precinct 9 and its Retirement Unit keep what passes for order in " <>
              "Neo-Meridian. **Badge, gun and a pension nobody lives to collect.**",
          open_join: true,
          position: 0
        })

      for {name, salary, leader, position} <- [
            {"Cadet", 20, false, 0},
            {"Detective", 40, false, 1},
            {"Captain", 80, true, 2}
          ] do
        {:ok, _} =
          Guilds.create_rank(police, %{
            name: name,
            salary: salary,
            leader: leader,
            position: position
          })
      end

      {:ok, underground} =
        Guilds.create_guild(story, %{
          name: "Echo Underground",
          description:
            "A whispered network smuggling runaway Echoes out of the city. " <>
              "*Nobody joins: you are found.*",
          secret: true,
          open_join: false,
          position: 1
        })

      for {name, salary, leader, position} <- [
            {"Sympathizer", 0, false, 0},
            {"Runner", 15, false, 1},
            {"Voice", 30, true, 2}
          ] do
        {:ok, _} =
          Guilds.create_rank(underground, %{
            name: name,
            salary: salary,
            leader: leader,
            position: position
          })
      end

      if is_nil(Repo.get_by(Section, story_id: story.id, name: "The Safehouse")) do
        {:ok, _} =
          Forum.create_section(story, %{
            name: "The Safehouse",
            description: "Coded messages between the members of the Echo Underground.",
            visibility: "guild",
            guild_id: underground.id,
            position: 10
          })
      end

      if is_nil(Repo.get_by(Location, story_id: story.id, name: "Precinct 9 Briefing Room")) do
        {:ok, _} =
          Stories.create_location(story, %{
            name: "Precinct 9 Briefing Room",
            description:
              "Cold coffee, a flickering holo-board and the case files of the week. " <>
                "Badges only.",
            area: "270,90 360,90 360,170 270,170",
            color: "#7aa2ff",
            guild_id: police.id
          })
      end

      Stories.get_story!(story.id)
    else
      story
    end
  end

  ## Esiti and quests

  @sample_npc "Mara Quill"
  @sample_esito "Shadowing the Undercity fixer"
  @sample_quest "The Undercity Docks blackout"

  @doc """
  Enables the esiti and quests modules the first time, with a sample NPC
  informant, one resolved esito filed as her and one public quest she took
  part in, its rewards handed out. Later runs (or a GM who disabled the
  modules) leave everything as it is.
  """
  def seed_esiti_and_quests(story, admin) do
    if Repo.exists?(from e in Esito, where: e.story_id == ^story.id and e.title == @sample_esito) do
      story
    else
      {:ok, story} = Stories.set_module_enabled(story, :esiti, true)
      {:ok, story} = Stories.set_module_enabled(story, :quests, true)
      npc = seed_sample_npc(story, admin)
      pier = Repo.get_by(Location, story_id: story.id, name: "Undercity Docks")
      seed_sample_esito(story, admin, npc, pier)
      seed_sample_quest(story, admin, npc, pier)
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
          description: "An informant with a debt to every fixer on the docks.",
          is_npc: true,
          approval_status: "approved",
          reviewed_by_id: admin.id,
          reviewed_at: DateTime.utc_now(:second)
        })

      npc ->
        npc
    end
  end

  defp seed_sample_esito(story, admin, npc, pier) do
    now = DateTime.utc_now(:second)

    esito =
      Repo.insert!(%Esito{
        story_id: story.id,
        character_id: npc.id,
        user_id: admin.id,
        title: @sample_esito,
        body:
          "Mara follows the fixer known as *Gutter Saint* from the noodle bar to the " <>
            "docks, keeping to the rain shadows. **Who is he meeting?**",
        location_id: pier && pier.id,
        status: "resolved",
        claimed_by_id: admin.id,
        claimed_at: now,
        resolved_by_id: admin.id,
        resolved_at: now,
        outcome:
          "Gutter Saint meets a courier from the Tyrell-Kade arcology. A crate changes " <>
            "hands: its seal reads *Nexus lot 7*. Nobody noticed Mara.",
        effects: %{"targets" => [npc.name], "xp" => 0, "money" => 0}
      })

    Repo.insert!(%Message{
      esito_id: esito.id,
      user_id: admin.id,
      from_masters: true,
      author_name: "The masters",
      body: "Roll Stealth when you reach the docks: it is raining, that helps you."
    })
  end

  defp seed_sample_quest(story, admin, npc, pier) do
    if is_nil(Repo.get_by(Quest, story_id: story.id, title: @sample_quest)) do
      {:ok, quest} =
        Quests.create_quest(admin, story, %{
          "title" => @sample_quest,
          "summary" =>
            "The lights of the docks went out for an hour and three containers vanished. " <>
              "The crew followed the trail to a flooded warehouse and **got one back**.",
          "held_on" => Date.to_iso8601(Date.utc_today()),
          "visibility" => "public",
          "location_id" => pier && pier.id
        })

      {:ok, _} =
        Quests.add_participant(admin, story, quest, %{
          "character_id" => npc.id,
          "money" => "50",
          "note" => "Found the warehouse."
        })

      {:ok, _} = Quests.apply_rewards(admin, story, Quests.get_quest(story, quest.id))
    end
  end

  ## Diary and boards

  @sample_announcement "Welcome to Neo-Meridian"

  @sheet_template """
  ## Origins
  Where were you born, and who raised you?

  ## The scar
  What went wrong, once, and still follows you?

  ## Why Neo-Meridian
  What keeps you in the city when everyone else wants to leave?
  """

  @doc """
  Enables the diary and boards modules the first time: a sheet template for
  new characters (when none is set), a pinned welcome announcement, a notice
  board across the Undercity zone with a notice by the sample NPC, and a
  public diary entry of hers. Later runs leave everything as it is.
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
          "The rain never stops in **Neo-Meridian**, and neither do we. Read the " <>
            "*Guide*, create your character and meet the others on the Undercity Docks.\n\n" <>
            "Notice boards hang in the Undercity: pin your in-character notices there."
      })

      seed_sample_board(story, admin)
      Stories.get_story!(story.id)
    end
  end

  @calendar_months """
  Ashfall | 31 | Winter
  Coldwire | 28 | Winter
  Thawrain | 31 | Spring
  Greensmog | 30 | Spring
  Neonbloom | 31 | Spring
  Highglare | 30 | Summer
  Blackheat | 31 | Summer
  Stillair | 31 | Summer
  Rustwind | 30 | Autumn
  Longdark | 31 | Autumn
  Floodtide | 30 | Autumn
  Deadsignal | 31 | Winter
  """

  # {name, icon, description, weights and temperature ranges per season}
  @weather_table [
    {"Acid rain", "hero-beaker", "Yellow rain that eats paint and skin. Keep your hood up.",
     %{
       "Winter" => {30, 1, 7},
       "Spring" => {35, 8, 14},
       "Summer" => {15, 18, 25},
       "Autumn" => {40, 7, 13}
     }},
    {"Smog", "hero-eye-slash", "A brown haze swallows the towers; the neon glows through it.",
     %{
       "Winter" => {20, 0, 6},
       "Spring" => {20, 10, 16},
       "Summer" => {35, 24, 33},
       "Autumn" => {20, 8, 14}
     }},
    {"Neon drizzle", "hero-cloud-arrow-down",
     "Fine, endless rain glittering with the signs' colours.",
     %{
       "Winter" => {25, 2, 8},
       "Spring" => {25, 9, 15},
       "Summer" => {15, 19, 26},
       "Autumn" => {25, 8, 14}
     }},
    {"Electric storm", "hero-bolt",
     "Lightning over the bay; the grid flickers district by district.",
     %{
       "Winter" => {10, 3, 9},
       "Spring" => {10, 12, 18},
       "Summer" => {25, 22, 30},
       "Autumn" => {10, 10, 16}
     }},
    {"Clear night", "hero-moon", "For once the sky is clean: cold stars above the spires.",
     %{
       "Winter" => {15, -4, 3},
       "Spring" => {10, 6, 12},
       "Summer" => {10, 16, 22},
       "Autumn" => {5, 4, 10}
     }}
  ]

  @doc """
  Enables the calendar and weather modules the first time: a noir calendar
  running in real time in 2121 (from today's date), a rain-heavy seasonal
  weather table and a first weather for every zone. Later runs leave
  everything as it is.
  """
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
          "epoch_year" => 2121,
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

  defp seed_sample_board(story, admin) do
    zone = Repo.get_by(Zones.Zone, story_id: story.id, name: "Undercity")
    room = Repo.get_by(Location, story_id: story.id, name: "Undercity Docks")
    npc = Repo.get_by(Character, story_id: story.id, name: @sample_npc)

    if zone || room do
      board =
        Repo.insert!(%Board{
          story_id: story.id,
          name: "Undercity wall",
          description: "Flyers, wanted posters and favours, glued over each other.",
          zone_id: zone && zone.id,
          location_id: if(zone, do: nil, else: room.id)
        })

      if npc do
        Repo.insert!(%Notice{
          board_id: board.id,
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "Information for sale",
          body: "Lost something on the docks? *I know who took it.* Ask at the noodle bar."
        })

        Repo.insert!(%Entry{
          story_id: story.id,
          character_id: npc.id,
          user_id: admin.id,
          title: "Rain shadows",
          game_date_label: "The night of the blackout",
          visibility: "public",
          body:
            "Followed the Gutter Saint again. He thinks the rain hides him; " <>
              "it only hides **me**."
        })
      end
    end
  end

  ## Items

  @doc """
  Enables the items module on the default story and seeds a few items and the
  "Black market" shop in the Neon Bazaar the first time (an admin who later
  disables the module keeps it off). Returns the (possibly updated) story.
  """
  def seed_items(story) do
    if Items.list_items(story) == [] do
      {:ok, story} = Stories.set_module_enabled(story, :items, true)
      slugs = Sheet.slugs(story)
      # The medkit heals a "health" tracker, if the GDR admin defined one.
      health = Enum.find(Trackers.list_trackers(story), &(&1.slug == "health"))

      {:ok, medkit} =
        Items.create_item(
          story,
          Map.merge(
            %{
              name: "Medkit",
              category: "Medical",
              price: 50,
              description:
                "Synth-skin patches, a painkiller auto-injector and a stapler. " <>
                  "*Not* street-legal without a Precinct permit."
            },
            medkit_effect(health)
          )
        )

      {:ok, blaster} =
        Items.create_item(story, %{
          name: "Blaster pistol",
          category: "Weapons",
          price: 400,
          stackable: false,
          slot: "weapon",
          modifiers: Map.take(%{"firearms" => 1}, slugs),
          description:
            "A heavy, double-trigger sidearm, the kind Wardens carry. " <>
              "Loud enough to stop an Echo, and a conversation."
        })

      {:ok, coat} =
        Items.create_item(story, %{
          name: "Trench coat",
          category: "Clothing",
          price: 120,
          stackable: false,
          slot: "body",
          modifiers: Map.take(%{"streetwise" => 1}, slugs),
          description: "Long, waxed and rain-proof. In the Undercity nobody looks twice at it."
        })

      bazaar = Enum.find(Stories.list_locations(story), &(&1.name == "Neon Bazaar"))

      {:ok, shop} =
        Items.create_shop(story, %{
          name: "Black market",
          location_id: bazaar && bazaar.id,
          description:
            "Behind a noodle-steam curtain in the Neon Bazaar, Mama Oyelaran sells what " <>
              "the Precincts would rather you didn't own. Cash only, no questions."
        })

      {:ok, _} = Items.create_listing(story, shop, %{item_id: medkit.id, stock: 10, position: 0})
      {:ok, _} = Items.create_listing(story, shop, %{item_id: blaster.id, stock: 2, position: 1})
      {:ok, _} = Items.create_listing(story, shop, %{item_id: coat.id, price: 100, position: 2})

      story
    else
      story
    end
  end

  defp medkit_effect(nil), do: %{}

  defp medkit_effect(%{damage_types: [type | _]} = tracker),
    do: %{tracker_id: tracker.id, effect_change: -2, effect_damage_type: type}

  defp medkit_effect(tracker), do: %{tracker_id: tracker.id, effect_change: 2}

  ## Guide and zones

  @doc "Seeds the guide of the default story when it has none."
  def seed_guide(story) do
    if Guide.list_sections(story) == [] do
      {:ok, world} = Guide.create_section(story, %{title: "The world", position: 0})

      [{"Background", world_background()}, {"Rules", rules()}, {"Customs", customs()}]
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

  @doc "Seeds the zones of the default city when it has none."
  def seed_zones(story) do
    if Zones.list_zones(story) == [] do
      {:ok, _} =
        Zones.create_property(story, %{name: "Danger", slug: "danger", default_value: 2})

      {:ok, _} =
        Zones.create_property(story, %{
          name: "Surveillance",
          slug: "surveillance",
          default_value: 3,
          public: false
        })

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
      {"Upper tiers", "Corporate towers above the haze, watched by every lens in the city.",
       %{"danger" => 1, "surveillance" => 5},
       ["Zenith Spire", "Precinct 9 Station", "Sentinel Tower Rooftop"]},
      {"Undercity", "Canals, markets and alleys where nobody asks your name.",
       %{"danger" => 4, "surveillance" => 1},
       [
         "Neon Bazaar",
         "Ozu's Noodle Counter",
         "Old Arcade Hotel",
         "Lacuna Memory Atelier",
         "Undercity Docks"
       ]}
    ]
  end

  ## Lore

  defp rules do
    """
    Tannhauser Gate is a noir cyberpunk role play set in Neo-Meridian, 2121.

    1. Play your character, not yourself. Speak in the rooms of the city through your character.
    2. Characters start with 1 to 5 points in each attribute, up to 5 in skills and up to 3 in powers. Spend them as you like within those limits.
    3. Echoes live at most six years; humans and Echoes are equals at the table. No player may kill another player's character without their consent.
    4. Keep the tone noir: rain, neon, moral grey. Keep it respectful: no real-world hate, no harassment.
    5. Earn credits through your job; the Warden desk and the Bazaar pay once a day. You can send credits to other characters from the bank.
    6. The game master has the final word on any dispute.
    """
  end

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
