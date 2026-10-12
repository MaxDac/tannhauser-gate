defmodule TannhauserGate.PeriodicActions do
  @moduledoc """
  Periodic (hunt-like) actions configured by the GDR admin.

  A player performs an action with a playable character from a location
  (`perform/4`): the dice pool is rolled with `TannhauserGate.Dice.roll/3`
  against the difficulty (the zone property of the location's zone, or the
  per-character difficulty set by the masters, falling back to the action's
  default), then the success or failure effect is applied with
  `TannhauserGate.Trackers.adjust/3` and the run is logged for the masters.
  An action can be performed again once its cooldown has elapsed; masters
  can reset a character's cooldown.

  Permission checks are the caller's job (see `Characters.can_act_as?/2`).
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Dice
  alias TannhauserGate.PeriodicActions.{Action, Difficulty, Log}
  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.{Location, Story}
  alias TannhauserGate.Trackers
  alias TannhauserGate.Zones

  @success_outcomes ~w(success critical messy_critical)

  ## Definitions (GDR admin)

  def list_actions(%Story{id: story_id}) do
    Repo.all(
      from a in Action,
        where: a.story_id == ^story_id,
        order_by: [asc: a.position, asc: a.name, asc: a.id]
    )
  end

  def get_action!(%Story{id: story_id}, id), do: Repo.get_by!(Action, id: id, story_id: story_id)

  def create_action(%Story{} = story, attrs) do
    %Action{story_id: story.id} |> Action.changeset(attrs, context(story)) |> Repo.insert()
  end

  def update_action(%Action{} = action, attrs) do
    action
    |> Action.changeset(attrs, context(%Story{id: action.story_id}))
    |> Repo.update()
  end

  def delete_action(%Action{} = action), do: Repo.delete(action)

  def change_action(%Action{} = action, attrs \\ %{}),
    do: Action.changeset(action, attrs, context(%Story{id: action.story_id}))

  defp context(%Story{} = story) do
    %{
      items: Sheet.slugs(story),
      trackers: Trackers.list_trackers(story),
      properties: Zones.property_slugs(story)
    }
  end

  ## Difficulty

  @doc """
  The difficulty of the action for a character performing it at a location
  (nil when the character performs it from nowhere).
  """
  def difficulty(%Action{difficulty_source: "zone"} = action, _character, location) do
    with %Location{} <- location,
         %{} = zone <- Zones.zone_of(location),
         value when is_integer(value) <- Zones.value(zone, action.zone_property) do
      value
    else
      _ -> action.default_difficulty
    end
  end

  def difficulty(%Action{} = action, %Character{} = character, _location) do
    case Repo.get_by(Difficulty, action_id: action.id, character_id: character.id) do
      %Difficulty{difficulty: value} -> value
      nil -> action.default_difficulty
    end
  end

  @doc "The per-character difficulties of an action, `character_id => difficulty`."
  def character_difficulties(%Action{id: action_id}) do
    Repo.all(
      from d in Difficulty,
        where: d.action_id == ^action_id,
        select: {d.character_id, d.difficulty}
    )
    |> Map.new()
  end

  @doc "Sets (or with nil/\"\" clears) the per-character difficulty of an action."
  def set_difficulty(%Action{} = action, %Character{} = character, value)
      when value in [nil, ""] do
    Repo.delete_all(
      from d in Difficulty, where: d.action_id == ^action.id and d.character_id == ^character.id
    )

    {:ok, nil}
  end

  def set_difficulty(%Action{} = action, %Character{} = character, value) do
    true = action.story_id == character.story_id

    (Repo.get_by(Difficulty, action_id: action.id, character_id: character.id) ||
       %Difficulty{action_id: action.id, character_id: character.id})
    |> Difficulty.changeset(%{difficulty: value})
    |> Repo.insert_or_update()
  end

  ## Cooldown

  @doc """
  The seconds left before the character can perform the action again
  (0 when it can).
  """
  def cooldown_remaining(%Action{} = action, %Character{} = character, now \\ DateTime.utc_now()) do
    case last_counted_run(action, character) do
      nil ->
        0

      performed_at ->
        ready_at = DateTime.add(performed_at, action.cooldown_hours * 3600, :second)
        max(DateTime.diff(ready_at, now, :second), 0)
    end
  end

  defp last_counted_run(action, character) do
    Repo.one(
      from l in Log,
        where:
          l.action_id == ^action.id and l.character_id == ^character.id and l.counts_for_cooldown,
        select: max(l.inserted_at)
    )
  end

  @doc "Lets the character perform the action again right away."
  def reset_cooldown(%Action{} = action, %Character{} = character) do
    {count, _} =
      Repo.update_all(
        from(l in Log,
          where:
            l.action_id == ^action.id and l.character_id == ^character.id and
              l.counts_for_cooldown
        ),
        set: [counts_for_cooldown: false]
      )

    {:ok, count}
  end

  ## Perform

  @doc """
  Performs the action for the character at the location: rolls, applies
  the effect and logs the run. Options: `:user` (who performed it),
  `:rng` (passed to `Dice.roll/3`), `:now`.

  Returns `{:ok, log}` or `{:error, reason}` (see `error_message/1`).
  """
  def perform(%Action{} = action, %Character{} = character, location, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now()) |> DateTime.truncate(:second)

    cond do
      action.story_id != character.story_id -> {:error, :wrong_story}
      location && location.story_id != action.story_id -> {:error, :wrong_story}
      true -> Repo.transaction(fn -> do_perform(action, character, location, now, opts) end)
    end
  end

  defp do_perform(action, character, location, now, opts) do
    # Serialize concurrent runs for the same character.
    Repo.one!(from c in Character, where: c.id == ^character.id, lock: "FOR UPDATE", select: c.id)

    if cooldown_remaining(action, character, now) > 0, do: Repo.rollback(:cooldown)

    story = Stories.get_story!(action.story_id)
    difficulty = difficulty(action, character, location)

    request = %{
      "items" => action.items,
      "modifier" => 0,
      "difficulty" => difficulty,
      "label" => action.name
    }

    result =
      case Dice.roll(character, request, story: story, rng: opts[:rng]) do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end

    success = result["outcome"] in @success_outcomes
    effect = apply_effect(action, character, success)

    Repo.insert!(%Log{
      action_id: action.id,
      character_id: character.id,
      user_id: opts[:user] && opts[:user].id,
      location_id: location && location.id,
      difficulty: difficulty,
      success: success,
      summary: String.slice(result["summary"] || "", 0, 255),
      effect: effect,
      result: result,
      inserted_at: now
    })
    |> Repo.preload([:action, :character, :location])
  end

  defp apply_effect(action, character, success) do
    {slug, type, delta} =
      if success,
        do: {action.success_tracker, action.success_damage_type, action.success_delta},
        else: {action.failure_tracker, action.failure_damage_type, action.failure_delta}

    if slug && delta != 0 do
      change = if type, do: {type, delta}, else: delta

      case Trackers.adjust(character, slug, change) do
        {:ok, state} -> describe_effect(state.tracker.name, type, delta)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp describe_effect(name, type, delta) do
    sign = if delta > 0, do: "+", else: ""
    Enum.join(Enum.reject([name, "#{sign}#{delta}", type], &is_nil/1), " ")
  end

  @doc "A human readable message for the `perform/4` errors."
  def error_message(:cooldown), do: "This action is still on cooldown."
  def error_message(:wrong_story), do: "This action belongs to another GDR."
  def error_message(reason), do: Dice.error_message(reason)

  ## Log (masters)

  @doc "The latest runs of the story's actions, newest first."
  def list_logs(%Story{id: story_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    query =
      from l in Log,
        join: a in assoc(l, :action),
        where: a.story_id == ^story_id,
        order_by: [desc: l.inserted_at, desc: l.id],
        limit: ^limit,
        preload: [:action, :character, :location, :user]

    query =
      case opts[:character_id] do
        nil -> query
        id -> where(query, [l], l.character_id == ^id)
      end

    Repo.all(query)
  end

  @doc "The last runs of a character, newest first (for the player)."
  def character_logs(%Character{id: id, story_id: story_id}, limit \\ 5),
    do: list_logs(%Story{id: story_id}, character_id: id, limit: limit)
end
