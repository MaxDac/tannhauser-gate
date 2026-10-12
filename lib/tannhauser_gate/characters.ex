defmodule TannhauserGate.Characters do
  @moduledoc """
  Characters of a story (GDR). Player characters belong to a user, who can have
  only one per GDR; NPCs belong to the GDR and are created and played by its
  masters. Attributes, skills and powers are numeric values for the sheet items
  defined by the GDR admin.

  Player characters start as drafts and must be approved by a master before
  they can play (`can_play?/1`); the GDR admin also defines character states,
  some of which (e.g. "Dead") forbid playing.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.{Character, State}
  alias TannhauserGate.Repo
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

  @doc "The (single) player character of the user in the given story, if any."
  def get_user_story_character(%User{id: user_id}, story_id) do
    Repo.one(
      from c in Character,
        where: c.user_id == ^user_id and c.story_id == ^story_id and not c.is_npc,
        preload: [:state]
    )
  end

  def get_character!(id),
    do: Character |> Repo.get!(id) |> Repo.preload([:user, :story, :job, :state, :reviewed_by])

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
  """
  def create_character(%User{} = user, attrs, avatar_path \\ nil) do
    %Character{user_id: user.id}
    |> Character.changeset(attrs)
    |> put_default_state()
    |> insert_with_traits(attrs, avatar_path)
  end

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

  defp insert_with_traits(changeset, attrs, avatar_path) do
    changeset =
      changeset
      |> maybe_put_avatar(avatar_path)
      |> validate_traits(attrs)

    Multi.new()
    |> Multi.insert(:character, changeset)
    |> Multi.run(:traits, fn repo, %{character: character} ->
      save_traits(repo, character, attrs)
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
  master-only notes can be changed too.
  """
  def update_character(%Character{} = character, attrs, avatar_path \\ nil, opts \\ []) do
    changeset =
      character
      |> Character.changeset(attrs, opts)
      |> maybe_put_avatar(avatar_path)
      |> validate_traits(attrs)

    Multi.new()
    |> Multi.update(:character, changeset)
    |> Multi.run(:traits, fn repo, %{character: updated} ->
      save_traits(repo, updated, attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  def delete_character(%Character{} = character), do: Repo.delete(character)

  def change_character(%Character{} = character, attrs \\ %{}, opts \\ []),
    do: character |> Character.changeset(attrs, opts) |> validate_traits(attrs)

  ## Approval

  @doc """
  Sends a draft (or a rejected character, after the owner's edits) to the
  masters for review. Returns `{:error, :invalid_status}` otherwise.
  """
  def submit_for_approval(%Character{approval_status: status} = character)
      when status in ["draft", "rejected"] do
    character |> Character.review_changeset("submitted", %{}) |> Repo.update()
  end

  def submit_for_approval(%Character{}), do: {:error, :invalid_status}

  @doc """
  Approves a character so it can play. Only the masters of its GDR (and the
  GDR/platform admins) can do it. `notes` are optional reviewer notes.
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
    if Stories.master?(reviewer, story_of(character)) do
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
  def approval_error_message(:invalid_status), do: "The character is already in that status."
  def approval_error_message(:notes_required), do: "Explain why the character is rejected."
  def approval_error_message(:unauthorized), do: "Only the GDR masters can review characters."
  def approval_error_message(:invalid_state), do: "That state does not exist in this GDR."
  def approval_error_message(%Ecto.Changeset{}), do: "The character could not be saved."

  @doc "A short label for an approval status."
  def approval_label("draft"), do: "Draft"
  def approval_label("submitted"), do: "Awaiting approval"
  def approval_label("approved"), do: "Approved"
  def approval_label("rejected"), do: "Rejected"
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
  The characters the user can act as in the story: their playable character,
  plus the playable NPCs when the user is a master.
  """
  def playable_characters(%User{} = user, %Story{} = story) do
    own = user |> list_user_characters(story.id) |> Enum.filter(&can_play?/1)

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
          "#{item.name} must be between #{item.min_value} and #{item.max_value}"
        )

      _ ->
        Ecto.Changeset.add_error(changeset, :traits, "#{item.name} must be a whole number")
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

  defp maybe_put_avatar(changeset, nil), do: changeset
  defp maybe_put_avatar(changeset, path), do: Character.avatar_changeset(changeset, path)
end
