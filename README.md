<p align="center">
  <img src="priv/static/images/logo.svg" alt="Tannhauser Gate" width="140">
</p>

<h1 align="center">Tannhauser Gate</h1>

<p align="center">
  A console-green, noir play-by-chat role-playing website built with Elixir, Phoenix LiveView and PostgreSQL.
</p>

---

Neo-Meridian, 2121. The acid rain never stops, the advertising never sleeps, and somewhere past
the orbital relay called the *Tannhauser Gate* the Echoes are coming home.

Tannhauser Gate is a small, self-hostable platform for running many text role-playing games
(GDRs). Each GDR is run by a game master (GM) with its own guide (world background, rules…), theme,
character sheet, map, forum, bank and jobs. Players pick a GDR after login, create one
character in it, and play in real-time chat rooms placed on its map. *Tannhauser Gate* is also
the name of the default GDR, an original setting inspired by the mood of *Blade Runner*.

## Features

- **Accounts:** email and password registration and login, built on `phx.gen.auth`. Users have two flags: `admin` and `gm` (game master). Registering requires ticking "I accept the terms and disclaimer" (linked to the static `/terms` page); the acceptance time is stored in `users.accepted_terms_at` (nil for accounts created before the checkbox existed).
- **GDR selection** (`/gdrs`): after login, players choose a published GDR to enter from the portal directory (see [Portal](#portal)). Each GDR lives under `/g/:id/...`.
- **Requesting a GDR:** a GM files a request (`/gdrs/request`). An admin approves or rejects it (`/admin/requests`). Approval creates a draft GDR owned by the GM. Each GM runs at most one GDR.
- **Roles per GDR** (helpers in `TannhauserGate.Stories`: `role/2`, `gdr_admin?/2`, `master?/2`):
  - **platform admin** (global `admin` flag): every power in every GDR;
  - **GDR admin**: the GM who owns the GDR; edits all of its configuration and picks its masters;
  - **masters**: narrators chosen by the GDR admin; they edit the GDR's characters, moderate its forum and use the master tools (`/g/:id/master`), but cannot change the configuration;
  - **players**: everyone else. Draft GDRs are visible only to their admin and masters.
- **Staff permissions** (core, `Stories.can?/3`): each master row (`story_masters`) carries six flags, all on by default: `can_moderate` (chat deletion, forum moderation, the moderation page and chat log, reports and sanctions), `can_approve_characters` (approval queue and character states), `can_award_xp`, `can_manage_esiti_quests`, `can_manage_economy` (item grants on sheets, items/shops master page), `can_manage_world` (zone events, action difficulties, calendar, weather, boards and announcements). The GDR admin ticks them per master in the GM **Masters** tab; the GDR admin and platform admins always hold every permission, players none. Pages check them with `on_mount {UserAuth, {:require_permission, perm}}` and the contexts check them again; the master tools only list the entries a master may use. `Stories.master?/2` still means "is staff" (visibility, narration, NPCs).
- **GM dashboard** (`/g/:id/gm`, only the GDR admin and platform admins):
  - name, summary, status (draft or published);
  - **modules** (`/g/:id/gm/modules`): switches for the optional features of the GDR (`TannhauserGate.Modules`). Each one is off by default; turning one off hides it from the players but keeps its data. Code checks them with `Stories.module_enabled?/2`, and module pages are guarded by the `{TannhauserGateWeb.UserAuth, {:require_module, key}}` on_mount hook;
  - the **community link**: an optional http(s) URL (e.g. a Discord server) with a label, shown in the GDR navigation as an external link;
  - the **guide** (`/g/:id/gm/guide`): sections holding ordered Markdown pages, edited with a live preview;
  - **zones** (`/g/:id/gm/zones`): numeric zone properties (name, key, default, visible to players or masters only) and zones with a value per property. Each room belongs to at most one zone, picked in the map tab;
  - **origins** (`/g/:id/gm/origins`, module *Races & classes*): origin groups (e.g. "Race", "Class") with a description, position and a *required* flag, each with options: a name, a Markdown description, an optional image, sheet bonuses (item key → ±N, validated against the GDR's item keys) and a *requires master approval* flag;
  - **items** (`/g/:id/gm/items`, module *Items & market*): the item catalog — name, Markdown description, optional image, category, base price, *stackable* flag, an optional equip slot (free text, e.g. "weapon"; an item with a slot is equippable), modifiers (item key → ±N, validated like origin bonuses) and an optional consumable effect (a tracker change, optionally on a damage type, and whether using it consumes one unit);
  - **shops** (`/g/:id/gm/shops`, module *Items & market*): shops with a description, optionally placed in a room, and their listings (item, price override, stock; an empty stock means unlimited);
  - **periodic actions** (`/g/:id/gm/actions`, e.g. a hunt): a dice pool of sheet items, a difficulty taken from a zone property of the room's zone or set by the masters per character (with a default), a tracker effect on success and on failure (a change, optionally on a damage type) and a cooldown in hours;
  - theme preset plus optional custom colours (hex only);
  - attributes, skills and powers, each with a name, description, min/max range and a key used in formulas (e.g. `strength`);
  - **creation and XP** per category (attribute/skill/power): free entry, a points pool (points to spend above the starting value) or a distribution (values like `4,3,3,2,2,2,1` to assign to items), the starting value, and the XP cost formula to raise an item by one point (e.g. `next * 5`);
  - **trackers** (health, willpower, hunger…): a name, a maximum given by a number or a formula over the item keys (e.g. `stamina + 3`), optional damage types (e.g. `superficial, aggravated`), whether it starts full and whether it is shown on the public sheet;
  - jobs and their pay, the currency name and the pay interval;
  - character balances (adjustments are recorded in the ledger);
  - map artwork and rooms (rooms can be flagged private);
  - **chat & dice:** the dice system and its parameters, and the chat archive age;
  - forum sections: name, description, position, **on game** (written in character) or off game, and **visibility** (all members, approved characters only, masters only);
  - masters (added by username, removed with one click);
  - character states (name, whether the character can play, position). Every GDR starts with an "Active" playable state.
- **Master tools** (`/g/:id/master`, masters, the GDR admin and platform admins): entry points to the GDR's characters, rooms and forum, plus the list of the GDR's narrators. They also include:
  - the **character dashboard** (`/g/:id/master/characters`): the approval queue (approve, or reject with notes), every character filtered by approval status, state and player/NPC, a state selector and the available/earned XP per row, links to edit any sheet, an XP award form (positive, or negative to correct, always with a reason) and the GDR XP log;
  - **NPC creation** (`/g/:id/master/npcs/new`);
  - **moderation** (`/g/:id/master/moderation`): the latest chat messages and forum posts of the GDR, each with a delete button. Masters can also delete messages directly in the chat rooms, and edit, delete, lock and pin forum topics and posts from the forum itself;
  - the **chat log** (`/g/:id/master/chat-log`): live and archived chat entries, filtered by room and dates;
  - **zone events** (`/g/:id/master/zones`): post events (title, Markdown body, in-game date) on a zone, and see every zone's values, hidden ones included;
  - **periodic actions** (`/g/:id/master/actions`): per action, set each character's difficulty, reset cooldowns and read the log of performed actions.
- **Characters:** each user can have up to `max_characters_per_user` characters per GDR (default 1, set by the GM from 1 to 10 in the General tab). Every non-NPC character counts, drafts and rejected ones included; NPCs never count. Creation checks the limit inside a transaction holding a per-user/GDR advisory lock, so concurrent requests cannot exceed it. With two or more characters, a selector under the GDR name in the drawer picks the **active character** (`user_active_characters`; if none is stored, the most recently updated playable one). The active character is used by the bank, jobs, market, guilds and home page, shown in presence, and is the default in the chat "Speak as", mail sender, forum author and esiti selectors, which still list all your playable characters. **Alt rules** (General tab, all on by default): `block_alt_transfers` (no bank transfers or item gifts between your own characters), `block_alt_mail` (no letters between them) and `block_alt_whispers` (no whispers between them, chat module). All three are enforced in the contexts. The character sheet, styled as a detective's spiral-bound notepad, shows the avatar, name, description, background and the GDR's attributes, skills and powers.
  - **Creation wizard:** players create their character step by step: identity, one step per category with items, then a review. Each step enforces the creation budget of its category on the server; categories without a budget accept any value within the item range. Masters (NPCs and edits) are never limited by the budgets. The owner can change trait values only until the character is approved; after that the sheet grows with XP.
  - **Approval:** new characters start as drafts. A draft can use every feature except playing. The owner submits it for approval; a master approves it or rejects it with notes. After a rejection the owner can edit the character and submit it again. Only characters that are approved *and* whose state allows playing can speak in character and roll dice in the chat rooms (`Characters.can_play?/1`); drafts can still post OFF.
  - **Visibility:** everyone sees the public sheet (avatar, name, description, background, off-game info, public trackers). The owner and the masters also see the full sheet (trait values, every tracker, XP totals and log, state, player notes). Master notes are visible only to the masters.
  - **Trackers:** each character has a current value (or damage per type) for every tracker of the GDR. Masters edit them from the sheet. Other features use `TannhauserGate.Trackers` (`get/2`, `adjust/3`, `set/3`, `set_damage/4`).
  - **Experience:** masters award XP with a reason. The owner of a playable character spends it from the sheet to raise an item by one point, at the cost of its category formula (never above the item maximum). Every award and spend is in the XP log, with earned, spent and available totals (`TannhauserGate.Experience`).
  - **Formulas** (`TannhauserGate.Formula`) are evaluated by a small safe parser, never by `Code.eval`: whole numbers, `+ - * /` (integer division), `min(a, b)`, `max(a, b)`, parentheses, item keys and the variables `current` and `next`. They are validated when saved.
  - **Origins** (`TannhauserGate.Origins`, module `:origins`): a character picks one option per origin group (`character_origins`), in an "Origins" wizard step right after identity; required groups must be chosen before submitting for approval. Like trait values, owners change origins only until approval, masters always (NPCs and edits). Options flagged *requires master approval* can be picked by players but are highlighted in the masters' approval queue, so approving the character approves them. Bonuses are added to the trait values in one place, `Characters.values_by_slug/1`, which feeds formulas, tracker maximums, dice pools and periodic actions; creation budgets and XP costs keep the base values, and the effective value may exceed the item maximum by the bonus. The public sheet shows the origins with their descriptions; the full sheet also shows the bonuses (base value and bonus next to each item), and the master character dashboard lists each character's origins. With the module off nothing applies.
  - **Items** (`TannhauserGate.Items`, module `:items`): characters hold items in an inventory (`character_items`, one row per item with a quantity; a non-stackable item is held at most once). The owner of a playable character equips and unequips items (one per slot: equipping another item in the same slot unequips the previous one), uses consumables (the effect goes through `Trackers.adjust/3`) and gives items to another approved character of the same GDR; masters grant, remove and equip items. Modifiers of equipped items are added in `Characters.values_by_slug/1` next to origin bonuses, so they feed dice pools, formulas and periodic actions, while creation budgets and XP keep the base values. The full sheet shows the inventory with its actions, the public sheet only the equipped items. Every grant, removal, gift, purchase, use, equip and unequip is recorded in the item log (`item_logs`), which masters read in the master tools (`/g/:id/master/items`), where they also grant and remove items.
  - **NPCs:** masters create non-player characters. NPCs are approved from the start and don't count toward the one-character limit. Masters pick an NPC (or their own character) in the chat "Speak as" selector.
- **Bank and jobs:** characters pick a job and receive its pay automatically every pay interval. They can send money to other characters of the same GDR. Every movement is stored in a transaction ledger.
- **Market** (`/g/:id/market`, module `:items`): lists every shop of the GDR with its listings, price and stock. A player with a playable character buys items in one transaction: it locks the character, decrements a limited stock with a conditional update (never below zero), adds the items to the inventory and debits the balance with `Bank.charge/4`, recorded in the ledger as a *purchase* ("Bought 2× Medkit at Black market"). Rooms with shops link them from their header. Selling items back is not supported.
- **Guilds and factions** (`TannhauserGate.Guilds`, module `:guilds`): masters manage the guilds of a GDR in the master tools (`/g/:id/master/guilds`): name, Markdown description, optional emblem, *secret* (the guild and its members are hidden from non-members), *open to requests* or invitation only, and ranks (name, order, salary per pay interval, *leader* flag). Players browse `/g/:id/guilds` and a guild page with its ranks and members. A character asks to join an open guild and a leader or master approves or rejects; leaders and masters invite approved player characters, and the owner accepts or declines from the guild page or the guild list; masters can also enrol any character (NPCs included) directly. Owners leave; leaders change the rank of and expel non-leader members other than their own characters (and can't assign leader ranks), masters do anything. A character belongs to at most *max guilds per character* guilds (GM general settings, default 1), checked when a membership becomes active under a row lock. Every request, invitation, join, refusal, rank change, departure and expulsion is recorded in the guild log, shown to leaders and masters. `Bank.Payer` also pays active members their rank salary once per pay interval since they joined (or were last paid), recorded as a "Guild salary: <guild> (<rank>)" pay entry. Forum sections can be restricted to a guild's members (visibility *Guild members*) and rooms can be reserved to a guild (only the players of its active members and the masters read and post there); both are set in the GM dashboard. Public sheets show a character's guilds and ranks (secret guilds only to their members and the masters) and the online list shows public guilds.
- **Chat roleplay** (module `:chat_rp`): *whispers* (entry kind `whisper`, to one approved character of the GDR, `messages.recipient_character_id`) are visible only to the sender, the owner of the recipient and the masters: the history, "load older" and live updates are filtered server-side (whispers are broadcast only on per-user and masters room topics, never on the public one; deletions only carry the id), and the chat log, moderation and archive keep the recipient. In-character entries take an optional *action tag* (max 40 characters, shown as "[at the bar]"), text between double quotes (“…”, "…" or «…») is highlighted as speech against the action/narration (`Chat.Speech.segments/1`, rendered as escaped text), and the GM sets a minimum and maximum length per in-character entry (GM "Chat & dice" tab), validated on posting and shown as a live counter in the composer. With the module off whispers are rejected and tags, highlighting and limits are ignored.
- **Esiti** (`TannhauserGate.Esiti`, module `:esiti`): the Italian chat-GDR staple of *action requests*. A player files an esito at `/g/:id/esiti` for one of their approved characters: title, Markdown body (sanitized), optional room or zone and other characters involved (same GDR). The masters get a letter from the character in their mailbox and a live counter (open requests) next to *Master tools* and on the master dashboard. Masters work the queue at `/g/:id/master/esiti` (filters: active, open, mine, in progress, resolved, closed, all; live updates), claim or release a request and discuss it in its thread on `/g/:id/esiti/:esito_id` (as *The masters* or signed with their name; the player writes as the character). Status: `open`, `claimed`, `resolved` or `closed` (withdrawn by the player or dismissed by a master); only the requester's owner and the masters can open a request. Resolving takes an outcome (Markdown) and optional effects applied in **one transaction** (any failure, e.g. taking money the character doesn't have or an unknown item, rolls everything back): a dice roll with the GDR dice system (`Dice.roll/3`, the same as the chat; the structured result is shown on the request), XP (`Experience`, reason "Esito: <title>"), money (`Bank.adjust/3`), an item (`Items.grant/5`, items module only) and a tracker change (`Trackers.adjust/3`), for the requester and optionally the related characters too. The outcome is sent to the requester as a letter from *The masters*. GDR limits (GM dashboard, *Esiti* tab): open requests per character (open + claimed, default 2, empty = unlimited) and the earned XP needed to file (empty = none).
- **Quest registry** (`TannhauserGate.Quests`, module `:quests`): masters record the quests they ran at `/g/:id/master/quests`: title, Markdown summary, date, optional room, the master who ran it, visibility (*public* or *masters only*) and an optional chat-log range that links the master chat log with the room and dates prefilled. Participants are characters of the GDR with per-participant rewards (XP, money, an item and quantity with the items module, a note). *Record and award* hands out every reward in one transaction (all or nothing: XP with reason "Quest: <title>", `Bank.adjust/3`, `Items.grant/5`) and marks the quest as rewarded under a row lock, so it can't happen twice; participants are then frozen. Everyone reads the public quests and their participants at `/g/:id/quests` (masters see all), and character sheets list the quests the character took part in (public ones; masters see all).
- **Rich character sheets** (core): a character's description, background and off-game info are Markdown, rendered sanitized with the Guide renderer (`<.markdown>`, raw HTML and scripts are dropped) on the sheet and the character list; plain text stays valid. The GDR admin sets a **sheet template** (GM dashboard, general tab, `stories.sheet_template`, Markdown) prefilled into the background of new characters and NPCs.
- **Diaries and gallery** (`TannhauserGate.Diary`, module `:diary`): each character has an in-character diary at `/g/:id/characters/:character_id/diary` (the sheet shows the three latest entries). An entry has a title, a Markdown body, an optional free-text in-game date (`game_date_label`, prefilled with the current game date when the calendar module is on) and a visibility: *public* (everyone in the GDR), *masters* (the owner and the masters) or *private* (meant for the owner only; the masters, GDR admin and platform admins can still read it **for moderation**, and the page says so). Only the owner writes a player's diary, the masters write NPC diaries, and the masters can delete any entry. The sheet also hosts a **gallery** of up to 12 pictures per character with a caption, managed by the owner and the masters and shown to everyone: PNG, JPEG or WebP only (checked from the file content, not the name), max 5 MB like avatars, stored through `TannhauserGate.Storage`.
- **Bulletin boards** (`TannhauserGate.Boards`, module `:boards`): masters post GDR **announcements** (title, Markdown, *pinned*, optional expiry) from `/g/:id/master/boards`; the GDR home lists the active ones, pinned first then newest, marking the new ones. Unread announcements are tracked per user and GDR (`announcement_reads.last_seen_at`, updated when the home page is opened) and counted in a badge on the Home drawer link, updated live (PubSub topic `"boards:story:#{id}"`). Masters also put up in-game **notice boards** hung in one room or across a whole zone (shown in every room of the zone, in a collapsible panel) and, with the guilds module on, optionally restricted to a guild (its active members and the masters, as for guild rooms). Players pin short notices (Markdown, max 1000 characters, optional expiry) signed by one of their playable characters (masters also by playable NPCs) on `/g/:id/boards`; authors take their notices down, masters any.
- **In-game calendar and clock** (`TannhauserGate.Calendar`, `TannhauserGate.Calendars`, module `:calendar`): the GDR admin configures a calendar in the GM **Calendar** tab (one `calendars` row per GDR): custom month names with their days and an optional season (`Name | days | season`, one per line), optional weekday names, an era label (e.g. `AE`) and a **ratio** (game seconds per real second: 1 = real time, 4 = four times faster). The game time is anchored to a real instant (`epoch_real` ↔ `epoch_year…epoch_minute`); `TannhauserGate.Calendar` is pure math (`to_game/2`, `format/2`). Masters move "now" from `/g/:id/master/calendar` (it re-anchors the epoch to the current real time). The current game date shows in the drawer under the GDR name and in the room header: the server renders it and a small colocated hook (`.GameClock`) advances it in the browser with the same math, so there is no server tick; changes reach open pages through PubSub (`"calendar:story:#{id}"`). With the module on, new diary entries, zone events and quests are prefilled with the current game date (still editable) and new esiti are stamped with it.
- **Reports and sanctions** (`TannhauserGate.Reports`, `TannhauserGate.Sanctions`, module `:reports`):
  - **Reports:** a small flag next to chat entries (not your own), forum posts, received letters, notices and character sheets opens `/g/:id/report?type=...&id=...`: a preview and a category (harassment, spam, metagame, rules, other) with optional details. The target must belong to the GDR and be visible to the reporter (whispers only to who can read them, hidden forum sections, only letters you received); its text is snapshotted into the report, so it survives deletion. One open report per user per target, at most 10 reports an hour.
  - **Queue** (`/g/:id/master/reports`, `can_moderate`): filters by status, content type and category; each open report is resolved or dismissed with notes, optionally deleting the chat entry, forum post or notice, and links to a sanction form prefilled with the author.
  - **Sanctions** (`/g/:id/master/sanctions`, `can_moderate`): *warning* (recorded only), *mute* and *ban* with a duration (1 hour to 30 days, or permanent) and a reason. The staff cannot be sanctioned. The page is the audit log (filters by kind, active status and user history) with a revoke action; sanctions are never deleted. The sanctioned user receives a letter from "The masters" and a flash on their next page.
  - **Enforcement** (only while the module is on): a ban stops the user at `UserAuth :load_story` (redirect to `/gdrs` with the end date and reason); a mute (or a ban) makes `Sanctions.check_not_muted/2` return `{:error, :muted}` from every write: chat entries (incl. OFF, whispers and dice), forum topics and posts, mail, notices and esiti.
- **Weather** (`TannhauserGate.Weather`, module `:weather`): each zone has a current weather (condition, icon, optional temperature and description, set by a master or *generated*). The GDR admin keeps a **weather table** in the GM **Weather** tab: conditions with an icon from a fixed set, a weight per season (the calendar seasons, or a single `default` season without the calendar) and optional min/max temperatures per season, plus the roll interval (`weather_interval_hours`, default 6). `TannhauserGate.Weather.Roller` (started outside tests, like the archiver) calls `Weather.roll_due/1` every 15 minutes: zones without weather, or whose weather is older than the interval, get a new weighted roll for the current season. A weather set by a master from `/g/:id/master/weather` (or a preset from the table, or a manual roll there) is kept for one interval. The weather shows in the room header (the room's zone) and on the map (an icon per room and a per-zone legend), updated live (`"weather:story:#{id}"`).
- **Automatic XP** (module `:auto_xp`, `Experience.award_chat_activity/4`): each in-character speech of a player character (not OFF, whispers, dice, narration or NPCs) of at least the minimum length awards the configured XP with reason "Chat activity" and `source: "auto"` on the XP entry, at most once per cooldown and up to a daily cap per character (UTC day), checked in a transaction holding a lock on the character. Settings in the GM "Chat & dice" tab; the master XP log (character dashboard) filters all/manual/automatic entries.
- **Left drawer navigation:** inside a GDR it covers Home, Characters, Map, Guide, Forum, Mail (with an unread badge), Bank, Jobs, Market (items module), Guilds (guilds module), Esiti (esiti module), Quests (quests module), Notice boards (boards module; the Home link shows the unread announcements), the master tools for its masters (with the number of open esiti) and the GM dashboard for its admin.
- **City map and chat rooms:** each GDR has an SVG map with clickable polygon areas. Every area is a chat room. Messages show the speaking character's avatar, name, time and text, and arrive live through Phoenix PubSub. GM artwork is rendered as an inert SVG image, so it can't run scripts.
  - **Entry types** (`TannhauserGate.Chat`): in-character speech (the default; the character must pass `Characters.can_play?/1`), **OFF** (out of character; allowed to the owner of any draft or approved character, rendered dimmed with an "OFF" badge), **narration** (masters only, posted as the "Narrator"), **room status** (masters only: sets the status text shown in the room header and logs it in the chat; an empty text clears it) and **dice** rolls.
  - **Dice** (`TannhauserGate.Dice`, always rolled on the server): every GDR picks its system in the GM dashboard: a generic `NdX+M` expression, d20 + modifier (with optional natural 20/1 criticals), or a **success pool** (die size, success threshold, default difficulty, "each pair of maxima adds N successes" criticals, optional special dice counted from a tracker such as hunger, with messy criticals and bestial failures). Rolls sum chosen sheet items into the pool or modifier, plus a manual modifier, an optional difficulty and a label. The structured result is stored on the dice entry and shown with every die. A pool GDR can configure a reroll: spend a tracker (e.g. willpower, or damage on a damage tracker) to reroll up to N failed regular dice once.
  - **History:** rooms show the latest 50 entries with a "Load older messages" button. An hourly job (`TannhauserGate.Chat.Archiver`) moves entries older than the GDR's archive age (default 30 days, empty = never) into `archived_messages`. Masters read live and archived entries in the **chat log** (`/g/:id/master/chat-log`), filtered by room and date range.
  - **Private rooms** (`TannhauserGate.Bookings`): the GDR admin flags rooms as private. A player with a playable character books a time slot (up to 12 hours, starting within 30 days, no overlaps) and invites characters. During a booking only the booker, the invitees' owners and the masters can read and post. Outside bookings only the masters can. Bookings are listed in the room and on the map.
- **Guide** (`TannhauserGate.Guide`, `/g/:id/guide`): every GDR has a guide of sections and ordered pages written in Markdown, rendered sanitized (raw HTML is dropped) with MDEx. Members read it from the drawer; its table of contents is also on the GDR home page, where the old fields used to be. The former world background, rules and customs fields were migrated into a "The world" section (the old columns are kept in the database but no longer used).
- **Zones** (`TannhauserGate.Zones`): rooms are grouped into zones carrying the GDR's numeric properties. A room shows its zone, the public property values (all of them for masters) and the latest zone events.
- **Periodic actions** (`TannhauserGate.PeriodicActions`): from a room, a player with a playable character performs a configured action. It rolls the dice pool with the GDR dice system against the difficulty (zone property of the room or per-character value), applies the success or failure effect through `Trackers.adjust/3`, starts the cooldown and logs the result. The result is shown to the player and in the masters' log.
- **Presence** (`TannhauserGateWeb.GdrPresence`): the drawer lists who is online in the GDR, with their character and current room, and a colored dot for their presence status. Each user picks *Available*, *Busy*, *Away* or *Looking for play* from the selector above the online list; the choice is saved per GDR (`presence_statuses`, `Stories.set_presence_status/3`), kept across pages and shown in the character quick-links menu too.
- **Return to chat:** entering a room remembers it as the user's last chat room in that GDR (`user_story_locations`, `Stories.remember_location/2` and `Stories.last_location/2`). The drawer (and the mobile top bar) shows a "Return to chat" link to it everywhere in the GDR except in that room.
- **Character quick links** (`<.character_quick_links>` in `TannhauserGateWeb.CharacterComponents`): character names in the online list, the chat speakers and the character list open a small menu to view the sheet, send a letter (compose page with the character prefilled) and, when the character is online in a room, go there. Public rooms are offered to everyone, private ones only to the masters (who can always enter them).
- **Mailbox** (`TannhauserGate.Mailbox`, `/g/:id/mail`): character-to-character letters inside one GDR. A message is sent *as* one of the characters the user can play (masters also as their NPCs or as "The masters") to any approved character, or to "The masters" (a shared mailbox read by every master). Masters can write to any character of the GDR. The inbox and sent views show read state; messages can be replied to (prefilled "Re:" subject) and deleted one by one or in bulk, independently on each side. The drawer shows the unread count, and a new letter flashes a live notification (PubSub topic `"mailbox:story:#{id}"`). Character pages have a "Send message" button and the master character dashboard a "Message owner" action.
- **Forum:** one forum per GDR: sections → topics → posts, with posts listed oldest first.
  - **On-game / off-game sections:** on-game topics and posts are written as one of the user's characters that can play (`Characters.can_play?/1`; masters can also write as NPCs); off-game ones are signed by the user.
  - **Visibility:** each section is visible to all members, to users with an approved character, or to masters only. Hidden sections are neither listed nor reachable.
  - **Editing and moderation:** authors edit and delete their own topics and posts (edited posts are marked). Masters can edit and delete anything, and **lock** (only masters can still reply) and **pin** (listed first) topics.
  - **Unread markers:** per user, each topic tracks the last read post (`forum_reads`); sections and topics with new posts are highlighted.
- **Admin control room:**
  - create and edit GDRs, their map artwork and rooms (polygon areas);
  - review GDR requests;
  - edit any character;
  - read and moderate every room's conversation;
  - moderate forum sections;
  - hide or unhide GDR reviews (`/admin/reviews`);
  - grant or revoke the admin and GM flags.
- **Default content:** the *Tannhauser Gate* GDR with nine rooms in the city of Neo-Meridian, attributes, skills, powers, jobs, three forum sections, a required "Origin" group (Human, or Replicant: +1 Body, −1 Empathy, requires master approval) with the origins module enabled, the items module with a Medkit (it heals a "health" tracker if the GDR defines one), a Blaster pistol (weapon, +1 Firearms) and a Trench coat (body, +1 Streetwise) sold at the "Black market" shop in the Neon Bazaar, the guilds module with the Meridian Police Department (open; Cadet, Detective and Captain ranks with salaries) and the secret Echo Underground (invitation only) with its guild forum section "The Safehouse" and the police-only "Precinct 9 Briefing Room", the chat roleplay module (entries up to 2000 characters) and automatic XP (1 XP per entry of at least 300 characters, cooldown 10 minutes, at most 10 a day), the esiti and quests modules with a sample NPC informant (Mara Quill), one resolved esito and one public quest with its rewards handed out, the diary and boards modules with a sheet template, a pinned "Welcome to Neo-Meridian" announcement, an "Undercity wall" notice board across the Undercity zone with a notice and a diary entry by Mara Quill, a directory listing (cyberpunk and mystery/noir, open, 16+, with a pitch), and an admin account.

## Portal

The platform-level storefront of the GDRs (`TannhauserGate.Directory`, always on, not a per-GDR module), inspired by the Italian play-by-chat directories.

- **Listing metadata** (on `stories`, GM **General** tab → *Directory listing*, also editable by platform admins in `/admin/stories/:id/edit` except the banner): up to 3 **genres** from a fixed list (`Directory.genres/0`: cyberpunk, fantasy, dark fantasy, sci-fi, horror, historical, modern, urban fantasy, anime/manga, post-apocalyptic, steampunk, superheroes, mystery/noir, other), a **lifecycle** (*Alpha test*, *Beta test*, *Open*, *Closed*; a badge only, independent from draft/published visibility; default open), a PEGI-like **content rating** (all, 12+, 16+, 18+; default 16+), a **pitch** (≤ 160 characters) and a **banner** (PNG, JPEG or WebP, checked from the file content, stored through `Storage`; `banner_path` is never cast from params).
- **Directory** (`/gdrs`, `GdrLive.Index`): cards with banner, name, pitch, genre chips, lifecycle and rating badges, average review score, members (distinct users with a non-NPC character), users online now (from `GdrPresence`) and votes this month, plus *Enter*. Visibility is unchanged: published GDRs, plus the drafts you run or master (admins see all). Filters (genre, status, rating, text search on name, pitch and summary) and the sort (*top rated*, *most voted this month*, *most active* = online then members, *newest*, *name*) live in the URL (`?genre=…&lifecycle=…&rating=…&q=…&sort=…`, `push_patch`); `Directory.list_directory/3` does the work.
- **GDR profile** (`/gdrs/:id`, `GdrLive.Profile`): banner, listing, summary, staff, counters, per-criterion score bars, the reviews, the vote button and *Enter*. GDRs the user cannot see redirect to the directory.
- **Reviews** (`gdr_reviews`): a 1–5 score for each criterion of the rubric — Graphics (*Grafica*), Setting (*Ambientazione*), In-game play level (*Livello di gioco interno*), Code & server (*Codice e server*), Features (*Funzionalità*), Documentation (*Documentazione*), Management (*Gestione*) — plus optional advice and required conclusions. The overall score is the mean of the criteria. A user can review a **published** GDR when they have an approved non-NPC character there created at least `review_min_days` days ago (config `:review_min_days`, default 14, `REVIEW_MIN_DAYS` at runtime) and are not its GDR admin or one of its masters; one review per user and GDR (unique index), editable by its author. The GDR admin (platform admins for platform-run GDRs) writes one reply per review, editable. Platform admins hide and unhide reviews from the profile page or `/admin/reviews`; hidden reviews disappear for everyone else and never count in scores, aggregates or the directory.
- **Votes and ranking** (`gdr_votes`, unique on story, user and month): any logged-in user votes once per calendar month (UTC) for each published GDR they can see (drafts cannot be voted). `/gdrs/ranking` shows this month's and the last 12 months' top 25 by votes, ties broken by average score.

## Stack

- [Phoenix 1.8](https://www.phoenixframework.org/) and Phoenix LiveView 1.2, generated from the latest `phx.new` skeleton
- Ecto 3 with PostgreSQL (`postgrex`)
- [Tailwind CSS v4](https://tailwindcss.com/) (CSS-first config, no `tailwind.config.js`) and [daisyUI 5](https://daisyui.com/)
- esbuild with colocated LiveView hooks, and heroicons
- Bandit HTTP server

## Theme

The UI uses a console / "Matrix" green palette tuned for long reading sessions. It is a custom
dark daisyUI theme called `tannhauser`. The primary phosphor green (#4ae08a) is deliberately softer
than pure #00ff00. It sits on a green-tinted near-black (`base-100`, #0b100d) instead of pure black,
and body text uses green-grey tones rather than saturated green. All text colours meet WCAG AA, and
most exceed AAA (phosphor is 11.3:1, body text 13.1:1). Red is reserved for errors and destructive
actions.

The theme, extra design tokens (`phosphor`, `mint`, `night`, `ink`, `fog-*`, fonts) and the
notepad, map and polaroid styles are all in [`assets/css/app.css`](assets/css/app.css).
UI components use daisyUI classes (`btn`, `input`, `select`, `drawer`, `alert`, ...).

`tannhauser` is the theme of the default GDR. The platform pages (GDR selection, account,
admin) use a neutral `platform` theme. GMs choose a preset for their GDR (`tannhauser`,
`ember`, `azure`, `crimson` or `sepia`) and can override its main colours with hex values. The
design tokens follow the active daisyUI theme, so the custom components restyle with it.

Shared form controls add scoped `console-field`, `console-check`, and `console-action` styles:
inset dark surfaces, readable borders, restrained green focus rings, and distinct error,
disabled, and read-only states. Labels stay visible, and field errors are associated through
`aria-describedby` without changing LiveView's validation timing. Reduced-motion preferences
disable control transitions. The theme remains flat for unrelated components.

`<.input class="...">` and `<.button class="...">` **replace** their default classes. Include
the complete control styling when overriding, for example
`class="w-full textarea console-field font-mono text-xs"` for a code textarea.

### Favicons

The existing `priv/static/favicon.svg` is the source for the browser icons. The root layout
prefers that scalable icon and also declares 16px/32px PNG fallbacks, a multi-size ICO
(16px/32px/48px), and a 180px Apple touch icon. All assets are served locally.

Regenerate them using the existing Playwright 1.64.0 dependency and its pinned Chromium:

```bash
cd e2e
npm ci
npx playwright install chromium
npm run generate:favicons
```

The generator renders each size directly from the unchanged SVG and packages the smaller
PNGs into the ICO; no extra image libraries or application dependencies are needed.

## Running locally (WSL / Linux)

The project is developed and tested inside WSL (Ubuntu), but any Linux or macOS machine works.

### 1. Prerequisites

```bash
# Build tools and PostgreSQL
sudo apt update
sudo apt install -y build-essential git curl unzip postgresql inotify-tools
sudo service postgresql start
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"

# Erlang/OTP, Elixir and Node (with mise, asdf works the same way)
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && source ~/.bashrc
mise use -g erlang@29 elixir@1.20 node@22
```

Elixir 1.17 or newer is required (CI runs Elixir 1.20 / OTP 29 and PostgreSQL 18). Tailwind and esbuild binaries are downloaded by `mix setup`, so Node is only needed for the Playwright tests.

### 2. Set up and run

```bash
git clone https://github.com/MaxDac/tannhauser-gate.git
cd tannhauser-gate
mix setup          # deps, database, migrations, seeds, assets
mix phx.server     # http://localhost:4000
```

To work from a Windows checkout, run the same commands from the `/mnt/c/...` path inside WSL.
For faster file watching, clone the repo into the Linux filesystem instead (for example `~/code`).

### Database configuration

The dev and test environments read these optional variables:

| Variable | Default |
| --- | --- |
| `PGUSER` / `PGPASSWORD` | `postgres` / `postgres` |
| `PGHOST` | `localhost` |
| `DEV_DATABASE` | `tannhauser_gate_dev` |
| `PORT` | `4000` |

### Email authentication feature flag

Email delivery and verification are behind `FEATURE_EMAIL_AUTH` (`true` or `1` enables it; the default is off,
see `TannhauserGate.Features`). While it is off, users register with a username, an email and a password. No
email is sent, the email stays unverified and login is by username. Password reset, the confirmation pages and
the "forgot password" link are disabled. Turning it on restores the confirmation, reset and email-change flows,
and login accepts the username or the email. See the "Enable email" GitHub issue for the re-enable steps.

### Seeded GDRs and accounts

The seeds (`mix run priv/repo/seeds.exs`, also run by `mix setup`) are safe to re-run: they only create
what is missing and never overwrite edits. They create three GDRs:

- **Tannhauser Gate** — the default GDR (Neo-Meridian, 2121), with every module, trackers (Health,
  Stress), a d10 dice pool and the "Work the streets" periodic action.
- **Neon Republic** — a second, Sprawl-style cyberpunk GDR (Halcyon Bay, 2093): console riders on the
  Lattice, rogue constructs, combines and orbital clans. It ships with full placeholder content (map
  and rooms, zones, guide, forum, sheet, jobs, origins, items and shop, guilds, NPC, esito, quest,
  calendar, weather, trackers, a d6 dice pool and periodic actions).
- **Arkham Adrift** — cosmic horror with a light that does not go out, inspired by *Stygian: Reign of
  the Old Ones* (original lore): Arkham, 1923, torn from the world and adrift in a starless void.
  The Black Star cult worships the Old Ones, while the Lamplighters of St. Agnes keep the lamp burning
  and search for the Narrow Gate home. It uses the `sepia` theme and a static banner
  (`priv/static/images/gdr/`), with Dread (madness dice) and Grace (rerolls, restored by charity)
  trackers on a d10 pool, and the same full placeholder content as Neon Republic.

They also create a platform admin and one GM owner per GDR:

| Account | Username | Email | Password | Override with |
| --- | --- | --- | --- | --- |
| Platform admin | `admin` | `admin@tannhauser.gate` | `change-me-tannhauser-2121` | `ADMIN_USERNAME`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` |
| Tannhauser Gate GM | `tannhauser_gm` | `gm@tannhauser.gate` | `change-me-tannhauser-gm-2121` | `TG_GM_USERNAME`, `TG_GM_EMAIL`, `TG_GM_PASSWORD` |
| Neon Republic GM | `neon_gm` | `gm@neon.republic` | `change-me-neon-republic-2093` | `NR_GM_USERNAME`, `NR_GM_EMAIL`, `NR_GM_PASSWORD` |
| Arkham Adrift GM | `arkham_gm` | `gm@arkham.adrift` | `change-me-arkham-adrift-1923` | `AA_GM_USERNAME`, `AA_GM_EMAIL`, `AA_GM_PASSWORD` |

Every seeded account must **change its password at the first login**: until then, every page
redirects to **Settings**. Re-running the seeds never resets a changed password. Admins can promote
other users from **Admin → Users**.

## Tests

### Unit and LiveView tests (ExUnit)

```bash
mix test
```

These cover the contexts, authorization, the seeds, and every LiveView, including avatar uploads, admin access control, the formula evaluator, creation budgets and the wizard, trackers and XP.

**Coverage.** `mix test --cover` prints per-module coverage, writes an HTML report to `cover/`, and fails
when the total drops below the `test_coverage` threshold in `mix.exs`. CI and `mix precommit` both run
it, and CI uploads the report as the `coverage-report` artifact. When you add tests, raise the threshold
to the new total, rounded down, so coverage can only go up.

### End-to-end tests (Playwright)

The E2E suite lives in [`e2e/`](e2e). It runs headless Chromium against two `mix phx.server`
instances that share the seeded dev database. The first runs on `E2E_PORT`. The second runs on
`E2E_PORT + 1` with `FEATURE_EMAIL_AUTH=true`, for the email flows. Shared helpers live in
[`e2e/tests/helpers.ts`](e2e/tests/helpers.ts). Every spec creates its own uniquely named accounts and
data, so the suite can run repeatedly against the same database. The flows:

- **tannhauser**: register, create a character with an avatar through the wizard, approve it as the
  admin, open a room from the map, chat, reply on the forum, check that players are denied admin
  access, and check that the admin can read the conversation;
- **email-auth**: registration with the confirmation email, and password reset from the emailed link
  (read from the dev mailbox);
- **account**: change email and password in the settings, log out, then log in with the new password;
- **gdr-lifecycle**: an admin grants the GM role, then rejects one GDR request and approves another.
  The GM publishes the GDR and writes a guide, zone properties, zones and periodic actions, and a
  player reads the guide;
- **player**: take and quit a job, a GM balance adjustment, bank transfers, mail, and editing and
  deleting a character;
- **master**: the dashboard, NPC creation, speaking as an NPC, the chat log, moderation, and zone events;
- **form-controls**: focus, validation and mobile layout of the forms.

```bash
mix ecto.reset                     # fresh, seeded dev database
cd e2e
npm install
npx playwright install --with-deps chromium
npx playwright test
```

The suite changes the seeded admin password at its first login to `ADMIN_E2E_PASSWORD` (default:
the admin password with an `-e2e` suffix) and reuses it afterwards.

Set `E2E_PORT` to use a port other than 4000 (the suite also uses the next port), and `DEV_DATABASE` to point at another dev database. Locally, if a server is already running on either port, the suite reuses it, so pick free ports when another server is running. For example:

```bash
DEV_DATABASE=tannhauser_gate_e2e_dev E2E_PORT=4210 npx playwright test
```

### Screenshot tests (Playwright)

[`e2e/tests/visual`](e2e/tests/visual) takes full-page screenshots of the key pages and compares
them with the committed baselines in `e2e/tests/visual/__screenshots__/`. Covered pages: login,
register, characters (drawer layout), character sheet and form, map, room chat, forum, mailbox, and admin.

The screenshots stay deterministic because:

- they run against a separate `tannhauser_gate_visual` database filled with fixed fixtures
  ([`priv/repo/visual_seeds.exs`](priv/repo/visual_seeds.exs)), and every timestamp is pinned to 2121-11-03;
- CI runs them in the pinned `mcr.microsoft.com/playwright:v1.64.0-noble` container, which matches
  `@playwright/test` 1.64.0 exactly, so fonts and rendering never drift. Bump both together;
- the viewport, scale, locale (`en-GB`), time zone (UTC) and colour scheme are fixed. Animations,
  transitions, the caret, flash toasts and the LiveView progress bar are disabled or hidden.

```bash
e2e/scripts/visual-db.sh           # recreate the fixture database
cd e2e
VISUAL_PORT=4220 npm run test:visual   # default port 4002
```

**Updating baselines.** The baselines are Linux-only and must come from CI's container. After an
intentional UI change, open **Actions → Update screenshots → Run workflow** and pick your PR branch.
The workflow regenerates the PNGs, commits them to the branch and re-runs CI. Review the image diff
in the PR. Locally, `npm run test:visual:update` is useful for iterating, but don't commit
the PNGs it writes. When a check fails, the diffs are uploaded as the
`playwright-screenshots-report` artifact. Its `test-results-visual/**/*-actual.png` files are also
valid baselines. They were rendered in the same container, so you can copy them into
`__screenshots__/` (dropping the `-actual` suffix) if the update workflow isn't available.

## Quality gates

Every pull request to `main` must pass these CI jobs. They are enforced by the
[`main` ruleset](.github/rulesets/main.json):

| Check | Command |
| --- | --- |
| `compile` | `mix compile --warnings-as-errors` |
| `format` | `mix format --check-formatted` |
| `credo` | `mix credo --strict` |
| `dialyzer` | `mix dialyzer` (PLTs in `priv/plts`, cached in CI) |
| `mix test` | `mix test --cover` (fails below the coverage threshold) |
| `Playwright e2e` | `cd e2e && npx playwright test` |
| `Playwright screenshots` | `cd e2e && npm run test:visual` |

The branch must also be up to date with `main`, and review conversations must be resolved. Repository
admins can bypass the ruleset. To change the ruleset, edit the JSON and re-apply it:

```bash
gh api -X PUT repos/MaxDac/tannhauser-gate/rulesets/<id> --input .github/rulesets/main.json
```

## Uploads

Character avatars, origin images, item images and directory banners are stored on local disk and served from `/uploads`. By default they go to
`priv/static/uploads`. In production, set `UPLOADS_DIR` to a persistent directory. Uploads accept
`.jpg`, `.jpeg`, `.png`, `.webp` and `.gif` files.

## Fly.io development deployment

The deployment target is <https://tannhauser-gate.fly.dev>, with a separate legacy
Postgres cluster named `tannhauser-gate-db`. Both use one shared CPU and 256MB RAM
in Amsterdam (`ams`). The database runs Postgres 17.2 with 1GB encrypted storage.
The app has a separate 1GB encrypted `uploads` volume mounted at `/data` and sets
`UPLOADS_DIR=/data/uploads`, so avatars survive restarts and deployments. Volumes
have automatic daily snapshots retained for five days; a single volume is not
high availability or a substitute for an independent backup.

This development deployment uses `MIX_ENV=prod`: debug routes and the local
mailbox are not published. The root-owned container entrypoint prepares the
mounted uploads directory, then drops to `nobody` before starting the release.
The release files remain root-owned and are not writable by the application.

GitHub Actions deploys pushes to `main` and manual runs on `main` only after
**all seven existing quality gates** pass, including Dialyzer, E2E, and screenshots.
Pull requests and manual runs on other branches never deploy. Deployments are
serialized and are not cancelled by a newer `main` run; PR checks retain their
auto-cancel behavior. Docker builds run on the GitHub runner rather than a paid
remote builder. Deployment uses `--ha=false` and never creates a spare app Machine.

| Platform | Secret | Purpose |
| --- | --- | --- |
| GitHub repository `MaxDac/tannhauser-gate` | `FLY_API_TOKEN` | Deploy token scoped only to `tannhauser-gate`, expiring after 720 hours |
| Fly app `tannhauser-gate` | `DATABASE_URL` | Attachment to database `tannhauser_gate` with a dedicated non-superuser role |
| Fly app `tannhauser-gate` | `SECRET_KEY_BASE` | Persistent session signing/encryption key |

Create or renew the deploy token with
`fly tokens create deploy -a tannhauser-gate --expiry 720h`, capturing its output
privately and passing it through stdin to
`gh secret set FLY_API_TOKEN --repo MaxDac/tannhauser-gate`. Do not run token
generation on its own where the credential will be printed. Import runtime
secrets through stdin with `fly secrets import --stage -a tannhauser-gate`.
Never put credentials in files, logs, build arguments, workflow artifacts, or
commits. Verify only metadata with `gh secret list --repo MaxDac/tannhauser-gate`
and `fly secrets list -a tannhauser-gate`. Renew the token before it expires and
preserve `SECRET_KEY_BASE` between deployments.

Deployment runs `bin/migrate` on a temporary 256MB Machine and fails if migrations
fail. The attached role has `CREATE` only on its own database to install the
trusted `citext` extension; it is not a superuser. Database resets and seeds do
not run automatically. In particular, deployment never creates an admin with
the published development password. Bootstrap content/admin access separately
with a strong private password before using the site; the local setup commands
above are not production provisioning commands.

The app stops when idle and wakes on incoming requests, with no minimum-running
Machine. Cold starts and deployment downtime are expected, and open LiveView
connections may keep it running. Postgres stays running. IPv6 database access is
enabled and the app uses a two-connection pool. Public traffic is forced to HTTPS;
Fly's internal HTTP probe uses `GET /health`, which checks database connectivity
and returns `{"status":"ok"}` or HTTP 503 with `{"status":"unavailable"}`.

**Email delivery is disabled until a real provider and sender are configured.**
The production mail adapter reports a delivery error without logging message
contents. Confirmation and password-reset emails cannot be delivered; existing
authentication requirements are unchanged. The site does not expose a mailbox
or publish email links in logs.

**Minimum resources do not mean guaranteed free billing.** Legacy allowances,
if active, are shared across all apps in the organization. This additional app,
database, and uploads volume may exceed them, and migration Machines, snapshots,
network usage, and stopped Machine root filesystems follow Fly's billing rules.
Do not increase memory, add replicas, or allocate a paid dedicated IPv4 address
without reviewing costs. The app uses shared IPv4 and free IPv6 ingress.

For an authorized local deployment, use
`fly deploy --app tannhauser-gate --config fly.toml --local-only --ha=false --no-public-ips --yes`
after provisioning the shared ingress addresses and uploads volume. Image
rollbacks do not undo migrations or restore uploaded files; do not run destructive
down migrations automatically.

## Project layout

```
lib/tannhauser_gate/          domain: Accounts, Stories, Characters, Chat, Forum, Mailbox, Storage, Seeds
lib/tannhauser_gate_web/live/ LiveViews (characters, map, rooms, forum, mail, admin)
assets/css/app.css            Tailwind v4 + daisyUI theme (console-green palette, notepad styles)
assets/js/app.js              LiveSocket setup (hooks are colocated in the LiveViews)
priv/static/images/logo.svg   brand mark; priv/static/favicon.svg
e2e/                          Playwright end-to-end and screenshot tests
priv/repo/visual_seeds.exs    deterministic fixtures for the screenshot tests
.github/rulesets/main.json    branch ruleset for main (required checks)
```

## License

Tannhauser Gate is free software released under the
[GNU Affero General Public License v3.0](LICENSE).

You may use, study, modify and share it, including commercially. If you distribute it, **or run a
modified version as a network service**, you must release your complete source code under the
same license. Closed-source forks and closed hosted versions are not allowed: everything stays in the open.

*Blade Runner* is a trademark of its respective owners. This project is an original, unaffiliated
work inspired by the genre. All story text, map art and branding here were written for this project.
