defmodule TannhauserGate.Characters do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  Characters of a story (GDR). Player characters belong to a user, who can have
  up to `story.max_characters_per_user` of them per GDR (1 by default); NPCs
  belong to the GDR, are created and played by its masters and never count
  towards that limit. With more than one character, the user picks the one
  they are playing (the *active character*, `active_character/2`): the pages
  acting as the character (bank, jobs, market, guilds, chat, mail, forum and
  presence) default to it. Attributes, skills and powers are numeric values for the sheet items
  defined by the GDR admin.

  Player characters start as drafts and must be approved by a master before
  they can play (`can_play?/1`); the GDR admin also defines character states,
  some of which (e.g. "Dead") forbid playing.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.{ActiveCharacter, Character, State}
  alias TannhauserGate.Items
  alias TannhauserGate.Origins
  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet
  alias TannhauserGate.Sheet.{Item, Trait}
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  def list_characters do
    Repo.all(
      from c in Character,
        order_by: [asc: c.name, asc: c.id],
        preload: [:user, :story, :state]
    )
  end

  @doc """
  Lists the characters of a story. Supported filters (string keys, empty
  values ignored): `"approval_status"`, `"state_id"` (`"none"` for characters
  without a state) and `"npc"` (`"true"` or `"false"`).
  """
  def list_story_characters(story_id, filters \\ %{}) do
    from(c in Character,
      where: c.story_id == ^story_id,
      order_by: [asc: c.name, asc: c.id],
      preload: [:user, :job, :state]
    )
    |> filter_characters(filters)
    |> Repo.all()
  end

  defp filter_characters(query, filters) do
    Enum.reduce(filters, query, fn
      {_key, value}, query when value in [nil, ""] ->
        query

      {"approval_status", status}, query ->
        where(query, [c], c.approval_status == ^status)

      {"state_id", "none"}, query ->
        where(query, [c], is_nil(c.state_id))

      {"state_id", id}, query ->
        case Integer.parse(to_string(id)) do
          {int, ""} -> where(query, [c], c.state_id == ^int)
          _ -> query
        end

      {"npc", "true"}, query ->
        where(query, [c], c.is_npc)

      {"npc", "false"}, query ->
        where(query, [c], not c.is_npc)

      _, query ->
        query
    end)
  end

  @doc "The NPCs of a story."
  def list_npcs(story_id), do: list_story_characters(story_id, %{"npc" => "true"})

  @doc "The characters waiting for a master's review, oldest submission first."
  def list_approval_queue(story_id) do
    Repo.all(
      from c in Character,
        where: c.story_id == ^story_id and c.approval_status == "submitted",
        order_by: [asc: c.updated_at, asc: c.id],
        preload: [:user, :state]
    )
  end

  @doc "The player characters (never NPCs) of a user, optionally in one story."
  def list_user_characters(%User{id: user_id}, story_id \\ nil) do
    query =
      from c in Character,
        where: c.user_id == ^user_id and not c.is_npc,
        order_by: [asc: c.name, asc: c.id],
        preload: [:story, :state]

    query = if story_id, do: where(query, [c], c.story_id == ^story_id), else: query

    Repo.all(query)
  end

  @doc "The number of player characters (NPCs excluded) of the user in the story."
  def count_user_characters(%User{id: user_id}, story_id) do
    Repo.aggregate(
      from(c in Character,
        where: c.user_id == ^user_id and c.story_id == ^story_id and not c.is_npc
      ),
      :count
    )
  end

  @doc """
  Whether the user can create another player character in the story: they
  have fewer than `story.max_characters_per_user` of them (whatever their
  status: drafts, rejected and dead characters count too).
  """
  def can_create_character?(%User{} = user, %Story{} = story),
    do: count_user_characters(user, story.id) < max_characters(story)

  defp max_characters(%Story{max_characters_per_user: max}) when is_integer(max), do: max
  defp max_characters(_), do: 1

  ## Active character

  @doc """
  The character the user is playing in the story: the one they picked with
  `set_active_character/2` or, by default, their most recently updated
  playable character, then any of their characters. `nil` when the user has
  no player character in the story. The state is preloaded.
  """
  def active_character(user, story)
  def active_character(%User{} = user, %Story{id: story_id}), do: active_character(user, story_id)

  def active_character(%User{} = user, story_id) when is_integer(story_id) do
    user |> list_user_characters(story_id) |> pick_active(stored_active_id(user, story_id))
  end

  def active_character(_, _), do: nil

  @doc """
  The player characters of the user in the story and the active one among
  them, in a single round trip: `{characters, active | nil}`.
  """
  def user_characters_with_active(%User{} = user, story_id) when is_integer(story_id) do
    characters = list_user_characters(user, story_id)
    {characters, pick_active(characters, stored_active_id(user, story_id))}
  end

  defp stored_active_id(%User{id: user_id}, story_id) do
    Repo.one(
      from a in ActiveCharacter,
        where: a.user_id == ^user_id and a.story_id == ^story_id,
        select: a.character_id
    )
  end

  defp pick_active([], _id), do: nil

  defp pick_active(characters, id) do
    Enum.find(characters, &(&1.id == id)) ||
      characters |> Enum.filter(&can_play?/1) |> most_recent() ||
      most_recent(characters)
  end

  defp most_recent([]), do: nil

  defp most_recent(characters),
    do: Enum.max_by(characters, &{DateTime.to_unix(&1.updated_at), &1.id})

  @doc """
  Makes `character` the active character of `user` in its GDR. Only the owner
  of a player character can pick it (`{:error, :unauthorized}` otherwise).
  """
  def set_active_character(%User{id: user_id}, %Character{is_npc: false, user_id: user_id} = c) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      ActiveCharacter,
      [
        %{
          user_id: user_id,
          story_id: c.story_id,
          character_id: c.id,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [set: [character_id: c.id, updated_at: now]],
      conflict_target: [:user_id, :story_id]
    )

    {:ok, c}
  end

  def set_active_character(_, _), do: {:error, :unauthorized}

  @doc """
  Moves the active character of the user (if among `characters`) to the
  front of the list, so that selectors default to it.
  """
  def active_first(characters, %User{} = user, story_id) do
    own = Enum.filter(characters, &(not &1.is_npc and &1.user_id == user.id))

    if length(own) > 1 do
      case active_character(user, story_id) do
        nil -> characters
        active -> Enum.sort_by(characters, &(&1.id != active.id))
      end
    else
      characters
    end
  end

  @doc """
  Whether two characters are alts: different player characters of the same
  user. NPCs are never alts.
  """
  def alts?(%Character{is_npc: false, user_id: user_id, id: a}, %Character{
        is_npc: false,
        user_id: user_id,
        id: b
      })
      when a != b,
      do: true

  def alts?(_, _), do: false

  @alt_rules [:block_alt_transfers, :block_alt_mail, :block_alt_whispers]

  @doc """
  Whether the GDR of `a` forbids the interaction `rule` (one of
  `:block_alt_transfers`, `:block_alt_mail` and `:block_alt_whispers`, story
  settings) between `a` and `b` because they are alts (`alts?/2`).
  """
  def alts_blocked?(rule, %Character{} = a, %Character{} = b) when rule in @alt_rules,
    do: alts?(a, b) and alt_rule?(a, rule)

  # Read fresh: a preloaded story may predate the GM's last change.
  defp alt_rule?(%Character{story_id: story_id}, rule) do
    case Stories.get_story(story_id) do
      %Story{} = story -> Map.get(story, rule) == true
      nil -> false
    end
  end

  @doc "Drops from `characters` the alts of `character` when the GDR `rule` blocks them."
  def reject_blocked_alts(characters, rule, %Character{} = character) when rule in @alt_rules do
    if Enum.any?(characters, &alts?(character, &1)) and alt_rule?(character, rule),
      do: Enum.reject(characters, &alts?(character, &1)),
      else: characters
  end

  def get_character!(id),
    do: Character |> Repo.get!(id) |> Repo.preload([:user, :story, :job, :state, :reviewed_by])

  @doc "Like `get_character!/1`, but returns nil when the character does not exist."
  def get_character(id) do
    case Repo.get(Character, id) do
      nil -> nil
      character -> Repo.preload(character, [:user, :story, :job, :state, :reviewed_by])
    end
  end

  @doc """
  Returns the sheet of a character: `%{kind => [{item, value}]}` with every item
  of the GDR (missing values default to the item minimum).
  """
  def sheet(%Character{} = character) do
    values =
      Repo.all(from t in Trait, where: t.character_id == ^character.id)
      |> Map.new(&{&1.sheet_item_id, &1.value})

    items =
      Repo.all(
        from i in Item,
          where: i.story_id == ^character.story_id,
          order_by: [asc: i.position, asc: i.name]
      )

    grouped = Enum.group_by(items, & &1.kind, &{&1, Map.get(values, &1.id, &1.min_value)})
    Map.new(Item.kinds(), &{&1, Map.get(grouped, &1, [])})
  end

  @doc "Map of `sheet_item_id => value` for the character."
  def trait_values(%Character{id: nil}), do: %{}

  def trait_values(%Character{id: id}) do
    Repo.all(from t in Trait, where: t.character_id == ^id)
    |> Map.new(&{&1.sheet_item_id, &1.value})
  end

  @doc """
  Creates a player character owned by `user`, as a draft in the default state
  of its GDR. `attrs["traits"]` maps sheet item ids to values. `avatar_path`
  (optional) is the public path of an already stored avatar image.

  The creation budgets configured by the GDR admin (see
  `TannhauserGate.Sheet.budget_status/3`) are enforced: missing values get
  the category default and the complete set must fit the budgets.
  """
  def create_character(%User{} = user, attrs, avatar_path \\ nil) do
    attrs = stringify_keys(attrs)

    changeset =
      %Character{user_id: user.id}
      |> Character.changeset(attrs)
      |> put_default_state()

    {changeset, attrs} = apply_budgets(changeset, attrs, %{})

    insert_with_traits(changeset, attrs, avatar_path, fn repo ->
      check_character_limit(repo, user, changeset)
    end)
  end

  # Serializes the creations of the same user in the same GDR with a
  # transaction-scoped advisory lock, then counts their player characters
  # (every status: drafts and rejected ones count too) against the limit.
  defp check_character_limit(repo, user, changeset) do
    with story_id when is_integer(story_id) <- Ecto.Changeset.get_field(changeset, :story_id),
         %Story{} = story <- Stories.get_story(story_id) do
      repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "character_limit:#{user.id}:#{story_id}"
      ])

      max = max_characters(story)

      if count_user_characters(user, story_id) < max,
        do: {:ok, :ok},
        else: {:error, Ecto.Changeset.add_error(changeset, :story_id, limit_message(max))}
    else
      _ -> {:ok, :ok}
    end
  end

  defp limit_message(1), do: dgettext("domain", "you already have a character in this GDR")

  defp limit_message(max),
    do:
      dgettext("domain", "you already have the maximum number of characters in this GDR (%{max})",
        max: max
      )

  @doc """
  Creates an NPC of `story`. Only its masters (and GDR/platform admins) can
  do it; NPCs are approved from the start and not limited to one per user.
  """
  def create_npc(%User{} = master, %Story{} = story, attrs, avatar_path \\ nil) do
    if Stories.master?(master, story) do
      attrs = attrs |> stringify_keys() |> Map.put("story_id", story.id)

      %Character{
        user_id: master.id,
        is_npc: true,
        approval_status: "approved",
        reviewed_by_id: master.id,
        reviewed_at: now()
      }
      |> Character.changeset(attrs, master?: true)
      |> put_default_state()
      |> insert_with_traits(attrs, avatar_path)
    else
      {:error, :unauthorized}
    end
  end

  defp insert_with_traits(changeset, attrs, avatar_path, check \\ fn _repo -> {:ok, :ok} end) do
    changeset =
      changeset
      |> maybe_put_avatar(avatar_path)
      |> validate_traits(attrs)
      |> Origins.validate_choices(attrs)

    Multi.new()
    |> Multi.run(:limit, fn repo, _ ->
      case check.(repo) do
        {:error, changeset} -> {:error, %{changeset | action: :insert}}
        ok -> ok
      end
    end)
    |> Multi.insert(:character, changeset)
    |> Multi.run(:traits, fn repo, %{character: character} ->
      save_traits(repo, character, attrs)
    end)
    |> Multi.run(:origins, fn repo, %{character: character} ->
      save_origins(repo, character, attrs, changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  defp put_default_state(changeset) do
    case Ecto.Changeset.get_field(changeset, :story_id) do
      story_id when is_integer(story_id) ->
        case default_state(story_id) do
          %State{id: id} -> Ecto.Changeset.put_change(changeset, :state_id, id)
          nil -> changeset
        end

      _ ->
        changeset
    end
  end

  defp stringify_keys(attrs), do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  @doc """
  Updates a character. Pass `master?: true` when a master edits it, so the
  master-only notes can be changed too and the sheet is not restricted.

  Without `master?`, the owner of a player character can change its trait
  values only before approval (within the creation budgets); once approved,
  submitted traits are ignored and items are raised by spending XP
  (`TannhauserGate.Experience.spend/3`). The same rule applies to the origins
  (`attrs["origins"]`, see `TannhauserGate.Origins`).
  """
  def update_character(%Character{} = character, attrs, avatar_path \\ nil, opts \\ []) do
    attrs = stringify_keys(attrs)
    {changeset, attrs} = owner_sheet_rules(character, attrs, opts)

    changeset =
      changeset
      |> maybe_put_avatar(avatar_path)
      |> validate_traits(attrs)
      |> Origins.validate_choices(attrs)

    Multi.new()
    |> Multi.update(:character, changeset)
    |> Multi.run(:traits, fn repo, %{character: updated} ->
      save_traits(repo, updated, attrs)
    end)
    |> Multi.run(:origins, fn repo, %{character: updated} ->
      save_origins(repo, updated, attrs, changeset)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  defp owner_sheet_rules(character, attrs, opts) do
    changeset = Character.changeset(character, attrs, opts)

    cond do
      opts[:master?] || character.is_npc ->
        {changeset, attrs}

      character.approval_status == "approved" ->
        {changeset, Map.drop(attrs, ["traits", "origins"])}

      not is_map(attrs["traits"]) ->
        {changeset, attrs}

      true ->
        apply_budgets(changeset, attrs, trait_values(character))
    end
  end

  @doc """
  Whether the owner can still set the trait values directly (before approval).
  Approved characters raise their items with XP instead.
  """
  def sheet_editable_by_owner?(%Character{is_npc: false, approval_status: status}),
    do: status != "approved"

  def sheet_editable_by_owner?(_), do: false

  @doc """
  Map of `slug => value` for every sheet item of the character's GDR
  (missing values default to the item minimum), used to evaluate formulas,
  tracker maximums and dice pools.

  These are the *effective* values: the origin bonuses
  (`TannhauserGate.Origins.bonuses/1`) are added when the origins module is
  enabled, and the modifiers of the equipped items
  (`TannhauserGate.Items.equipment_modifiers/1`) when the items module is, so
  they may exceed the item maximum. Creation budgets and XP costs
  use the base values (`sheet/1`, `trait_values/1`) instead.
  """
  def values_by_slug(%Character{} = character) do
    character
    |> sheet()
    |> Enum.flat_map(fn {_kind, entries} -> Enum.map(entries, fn {i, v} -> {i.slug, v} end) end)
    |> Map.new()
    |> Origins.apply_bonuses(Origins.bonuses(character))
    |> Origins.apply_bonuses(Items.equipment_modifiers(character))
  end

  # Fills missing values with the category defaults and checks the creation
  # budgets. Returns the changeset (with budget errors on :traits) and the
  # attrs carrying the complete set of values to persist.
  defp apply_budgets(changeset, attrs, base_values) do
    with story_id when is_integer(story_id) <- Ecto.Changeset.get_field(changeset, :story_id),
         %Story{} = story <- Stories.get_story(story_id) do
      items_by_kind = Sheet.items_by_kind(story)
      categories = Sheet.categories(story)
      params = if is_map(attrs["traits"]), do: attrs["traits"], else: %{}

      submitted =
        items_by_kind
        |> Map.values()
        |> List.flatten()
        |> trait_values_from(params)
        |> Map.new()

      values =
        base_values
        |> Map.merge(submitted)
        |> Sheet.with_defaults(items_by_kind, categories)

      changeset =
        items_by_kind
        |> Sheet.creation_errors(categories, values)
        |> Enum.reduce(changeset, fn {_kind, message}, acc ->
          Ecto.Changeset.add_error(acc, :traits, message)
        end)

      # Keep unparseable submitted values so validate_traits reports them.
      traits =
        Map.merge(
          params,
          Map.new(values, fn {id, v} -> {to_string(id), v} end),
          &keep_unparseable/3
        )

      {changeset, Map.put(attrs, "traits", traits)}
    else
      _ -> {changeset, attrs}
    end
  end

  defp keep_unparseable(_id, raw, value),
    do: if(match?({_, ""}, parse_int(raw)), do: value, else: raw)

  def delete_character(%Character{} = character), do: Repo.delete(character)

  def change_character(%Character{} = character, attrs \\ %{}, opts \\ []),
    do:
      character
      |> Character.changeset(attrs, opts)
      |> validate_traits(attrs)
      |> Origins.validate_choices(stringify_keys(attrs))

  ## Approval

  @doc """
  Sends a draft (or a rejected character, after the owner's edits) to the
  masters for review. Returns `{:error, :invalid_status}` otherwise, or
  `{:error, :origins_missing}` when a required origin group has no choice.
  """
  def submit_for_approval(%Character{approval_status: status} = character)
      when status in ["draft", "rejected"] do
    if Origins.missing_required(character) == [] do
      character |> Character.review_changeset("submitted", %{}) |> Repo.update()
    else
      {:error, :origins_missing}
    end
  end

  def submit_for_approval(%Character{}), do: {:error, :invalid_status}

  @doc """
  Approves a character so it can play. Only the masters of its GDR holding the
  `:can_approve_characters` staff permission (and the GDR/platform admins) can
  do it. `notes` are optional reviewer notes.
  """
  def approve_character(%Character{} = character, %User{} = reviewer, notes \\ nil) do
    review(character, reviewer, "approved", notes)
  end

  @doc """
  Rejects a character, explaining why in `notes` (required). The owner can
  edit it and submit it again.
  """
  def reject_character(%Character{} = character, %User{} = reviewer, notes) do
    if blank?(notes),
      do: {:error, :notes_required},
      else: review(character, reviewer, "rejected", notes)
  end

  defp review(%Character{approval_status: status}, _reviewer, status, _notes),
    do: {:error, :invalid_status}

  defp review(character, reviewer, status, notes) do
    if Stories.can?(reviewer, story_of(character), :can_approve_characters) do
      character
      |> Character.review_changeset(status, %{
        review_notes: if(blank?(notes), do: nil, else: String.trim(notes)),
        reviewed_by_id: reviewer.id,
        reviewed_at: now()
      })
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc "A human readable message for the approval errors."
  def approval_error_message(:invalid_status),
    do: dgettext("domain", "The character is already in that status.")

  def approval_error_message(:notes_required),
    do: dgettext("domain", "Explain why the character is rejected.")

  def approval_error_message(:unauthorized),
    do: dgettext("domain", "Only the GDR masters allowed to approve characters can review them.")

  def approval_error_message(:invalid_state),
    do: dgettext("domain", "That state does not exist in this GDR.")

  def approval_error_message(:origins_missing),
    do: dgettext("domain", "Choose every required origin before submitting the character.")

  def approval_error_message(%Ecto.Changeset{}),
    do: dgettext("domain", "The character could not be saved.")

  @doc "A short label for an approval status."
  def approval_label("draft"), do: dgettext("domain", "Draft")
  def approval_label("submitted"), do: dgettext("domain", "Awaiting approval")
  def approval_label("approved"), do: dgettext("domain", "Approved")
  def approval_label("rejected"), do: dgettext("domain", "Rejected")
  def approval_label(other), do: other

  ## Permissions

  @doc """
  Whether the character can play: it is approved and its state (if any)
  allows playing. Every in-game action (chat, and later on-game forum and
  dice) must check this.
  """
  def can_play?(%Character{approval_status: "approved"} = character) do
    case state_of(character) do
      nil -> true
      %State{can_play: can_play} -> can_play
    end
  end

  def can_play?(_), do: false

  @doc """
  Whether the user can act in game as the character: players act as their own
  playable character, masters as the playable NPCs of their GDR.
  """
  def can_act_as?(%User{} = user, %Character{is_npc: true} = character),
    do: can_play?(character) and Stories.master?(user, story_of(character))

  def can_act_as?(%User{id: user_id}, %Character{user_id: user_id} = character),
    do: can_play?(character)

  def can_act_as?(_, _), do: false

  @doc """
  The characters the user can act as in the story: their playable characters
  (the active one first), plus the playable NPCs when the user is a master.
  """
  def playable_characters(%User{} = user, %Story{} = story) do
    own =
      user
      |> list_user_characters(story.id)
      |> Enum.filter(&can_play?/1)
      |> active_first(user, story.id)

    npcs =
      if Stories.master?(user, story),
        do: story.id |> list_npcs() |> Enum.filter(&can_play?/1),
        else: []

    own ++ npcs
  end

  @doc """
  Owners (of player characters) and the masters of the character's GDR
  (including its GDR admin and platform admins) can edit a character.
  """
  def can_edit?(%User{} = user, %Character{} = character) do
    owner?(user, character) or Stories.master?(user, story_of(character))
  end

  def can_edit?(_, _), do: false

  @doc """
  Whether the user sees the full sheet (trait values, player notes and
  off-game info): the owner and the masters. Everyone else sees the public
  sheet: avatar, name, description and background.
  """
  def can_view_full_sheet?(user, character), do: can_edit?(user, character)

  @doc "Whether the user sees and edits the master-only notes."
  def can_view_master_notes?(%User{} = user, %Character{} = character),
    do: Stories.master?(user, story_of(character))

  def can_view_master_notes?(_, _), do: false

  defp owner?(%User{id: id}, %Character{is_npc: false, user_id: id}), do: true
  defp owner?(_, _), do: false

  defp story_of(%Character{story: %Story{} = story}), do: story
  defp story_of(%Character{story_id: story_id}), do: Stories.get_story(story_id)

  defp state_of(%Character{state_id: nil}), do: nil
  defp state_of(%Character{state: %State{} = state}), do: state
  defp state_of(%Character{state_id: id}), do: Repo.get(State, id)

  ## States

  @doc "The character states of a story, by position."
  def list_states(%Story{id: story_id}) do
    Repo.all(
      from s in State, where: s.story_id == ^story_id, order_by: [asc: s.position, asc: s.id]
    )
  end

  @doc "The state given to new characters: the first one by position."
  def default_state(story_id) do
    Repo.one(
      from s in State,
        where: s.story_id == ^story_id,
        order_by: [asc: s.position, asc: s.id],
        limit: 1
    )
  end

  def get_state!(%Story{id: story_id}, id), do: Repo.get_by!(State, id: id, story_id: story_id)

  def create_state(%Story{id: story_id}, attrs, repo \\ Repo) do
    %State{story_id: story_id} |> State.changeset(attrs) |> repo.insert()
  end

  @doc "Seeds the default \"Active\" playable state of a new story."
  def create_default_states(%Story{} = story, repo \\ Repo) do
    create_state(story, %{name: "Active", can_play: true, position: 0}, repo)
  end

  def update_state(%State{} = state, attrs), do: state |> State.changeset(attrs) |> Repo.update()

  @doc "Deletes a state; its characters are left without a state."
  def delete_state(%State{} = state), do: Repo.delete(state)

  def change_state(%State{} = state, attrs \\ %{}), do: State.changeset(state, attrs)

  @doc """
  Sets the state of a character (`nil` or `""` clears it). The state must
  belong to the character's GDR.
  """
  def set_state(%Character{} = character, state_id) when state_id in [nil, ""] do
    character |> Ecto.Changeset.change(state_id: nil) |> Repo.update()
  end

  def set_state(%Character{} = character, state_id) do
    with {id, ""} <- Integer.parse(to_string(state_id)),
         %State{} = state <- Repo.get_by(State, id: id, story_id: character.story_id) do
      character |> Ecto.Changeset.change(state_id: state.id) |> Repo.update()
    else
      _ -> {:error, :invalid_state}
    end
  end

  defp blank?(value), do: value in [nil, ""] or (is_binary(value) and String.trim(value) == "")
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  ## Traits

  defp validate_traits(changeset, attrs) do
    params = attrs["traits"] || attrs[:traits]
    story_id = Ecto.Changeset.get_field(changeset, :story_id)

    if is_map(params) and is_integer(story_id) do
      items = Repo.all(from i in Item, where: i.story_id == ^story_id)

      Enum.reduce(items, changeset, &check_submitted_trait(&1, params, &2))
    else
      changeset
    end
  end

  defp check_submitted_trait(item, params, changeset) do
    case fetch_param(params, item.id) do
      :error -> changeset
      {:ok, raw} -> check_trait(changeset, item, raw)
    end
  end

  defp submitted_traits(character, attrs) do
    params = attrs["traits"] || attrs[:traits]

    if is_map(params) do
      items = Repo.all(from i in Item, where: i.story_id == ^character.story_id)
      trait_values_from(items, params)
    else
      []
    end
  end

  defp trait_values_from(items, params) do
    for item <- items,
        {:ok, raw} <- [fetch_param(params, item.id)],
        {value, ""} <- [parse_int(raw)] do
      {item.id, value}
    end
  end

  defp check_trait(changeset, item, raw) do
    case parse_int(raw) do
      {value, ""} when value >= item.min_value and value <= item.max_value ->
        changeset

      {_, ""} ->
        Ecto.Changeset.add_error(
          changeset,
          :traits,
          dgettext_noop("errors", "%{name} must be between %{min} and %{max}"),
          name: item.name,
          min: item.min_value,
          max: item.max_value
        )

      _ ->
        Ecto.Changeset.add_error(
          changeset,
          :traits,
          dgettext_noop("errors", "%{name} must be a whole number"),
          name: item.name
        )
    end
  end

  defp fetch_param(params, id) do
    case Map.fetch(params, to_string(id)) do
      {:ok, ""} -> :error
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(params, id)
    end
  end

  defp parse_int(value) when is_integer(value), do: {value, ""}
  defp parse_int(value) when is_binary(value), do: Integer.parse(String.trim(value))
  defp parse_int(_), do: :error

  defp save_traits(repo, character, attrs) do
    case submitted_traits(character, attrs) do
      [] ->
        {:ok, 0}

      values ->
        # Lock the items so a concurrent range change by the GM waits for us
        # (or we see its new range), then keep values inside the range.
        ids = Enum.map(values, &elem(&1, 0))

        ranges =
          repo.all(
            from i in Item,
              where: i.id in ^ids,
              lock: "FOR SHARE",
              select: {i.id, {i.min_value, i.max_value}}
          )
          |> Map.new()

        rows =
          for {item_id, value} <- values,
              {lo, hi} <- [ranges[item_id]],
              do: %{
                character_id: character.id,
                sheet_item_id: item_id,
                value: value |> max(lo) |> min(hi)
              }

        {count, _} =
          repo.insert_all(Trait, rows,
            on_conflict: {:replace, [:value]},
            conflict_target: [:character_id, :sheet_item_id]
          )

        {:ok, count}
    end
  end

  defp save_origins(repo, character, attrs, changeset) do
    case Origins.save_choices(repo, character, attrs["origins"]) do
      {:ok, count} -> {:ok, count}
      {:error, message} -> {:error, Ecto.Changeset.add_error(changeset, :origins, message)}
    end
  end

  defp maybe_put_avatar(changeset, nil), do: changeset
  defp maybe_put_avatar(changeset, path), do: Character.avatar_changeset(changeset, path)
end
