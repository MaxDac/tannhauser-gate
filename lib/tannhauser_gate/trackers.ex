defmodule TannhauserGate.Trackers do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  Trackers are per-GDR resources configured by the GDR admin (health,
  willpower, hunger...) and tracked on every character.

  A tracker's maximum is a formula over the character's sheet items (see
  `TannhauserGate.Formula`). Simple trackers hold a current `value` between 0
  and the maximum; trackers with damage types (e.g. superficial and
  aggravated) hold an amount of damage per type, whose total never exceeds
  the maximum.

  This context performs no permission checks: callers (LiveViews, dice
  rolls, periodic actions) decide who may change a tracker. Use `adjust/3`
  to change a tracker atomically, e.g. `adjust(character, "hunger", 1)` or
  `adjust(character, "health", {"superficial", 2})`.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Formula
  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet
  alias TannhauserGate.Stories.Story
  alias TannhauserGate.Trackers.{CharacterTracker, Tracker}

  @type state :: %{
          tracker: struct(),
          max: non_neg_integer(),
          value: non_neg_integer(),
          damage: %{optional(String.t()) => non_neg_integer()},
          total_damage: non_neg_integer(),
          remaining: non_neg_integer(),
          error: String.t() | nil
        }

  ## Definitions (GDR admin)

  @doc "The trackers of a story, by position then name."
  def list_trackers(%Story{id: story_id}), do: list_trackers(story_id)

  def list_trackers(story_id) when is_integer(story_id) do
    Repo.all(
      from t in Tracker,
        where: t.story_id == ^story_id,
        order_by: [asc: t.position, asc: t.name, asc: t.id]
    )
  end

  def get_tracker!(%Story{id: story_id}, id),
    do: Repo.get_by!(Tracker, id: id, story_id: story_id)

  def create_tracker(%Story{} = story, attrs) do
    %Tracker{story_id: story.id}
    |> Tracker.changeset(attrs, Sheet.slugs(story))
    |> Repo.insert()
  end

  def update_tracker(%Tracker{} = tracker, attrs) do
    tracker
    |> Tracker.changeset(attrs, Sheet.slugs(%Story{id: tracker.story_id}))
    |> Repo.update()
  end

  def delete_tracker(%Tracker{} = tracker), do: Repo.delete(tracker)

  def change_tracker(%Tracker{} = tracker, attrs \\ %{}),
    do: Tracker.changeset(tracker, attrs, Sheet.slugs(%Story{id: tracker.story_id}))

  ## Character state

  @doc """
  The state of every tracker of the character's GDR. Pass
  `public_only: true` to get only the trackers visible to everyone.
  """
  @spec character_trackers(struct(), keyword()) :: [state()]
  def character_trackers(%Character{} = character, opts \\ []) do
    trackers =
      character.story_id
      |> list_trackers()
      |> then(&if opts[:public_only], do: Enum.filter(&1, fn t -> t.public end), else: &1)

    rows = rows_by_tracker(character, Enum.map(trackers, & &1.id))
    values = Characters.values_by_slug(character)

    Enum.map(trackers, &build_state(&1, Map.get(rows, &1.id), values))
  end

  @doc "The state of one tracker (by slug, id or struct), or nil."
  @spec get(struct(), struct() | String.t() | integer()) :: state() | nil
  def get(%Character{} = character, tracker_ref) do
    case resolve(character, tracker_ref) do
      nil ->
        nil

      tracker ->
        row = Repo.get_by(CharacterTracker, character_id: character.id, tracker_id: tracker.id)
        build_state(tracker, row, Characters.values_by_slug(character))
    end
  end

  @doc "The maximum of a tracker for a character's sheet values (`slug => value`)."
  def max_value(%Tracker{max_formula: formula}, values) do
    case Formula.evaluate(formula, values) do
      {:ok, max} -> {:ok, max(max, 0)}
      error -> error
    end
  end

  @doc """
  Changes a tracker by a delta, clamped into its range, and returns the new
  state. For trackers with damage types pass `{type, delta}`.
  """
  @spec adjust(struct(), struct() | String.t() | integer(), integer() | {String.t(), integer()}) ::
          {:ok, state()} | {:error, atom()}
  def adjust(character, tracker_ref, delta) when is_integer(delta) do
    change(character, tracker_ref, fn state -> {:value, state.value + delta} end)
  end

  def adjust(character, tracker_ref, {type, delta}) when is_integer(delta) do
    change(character, tracker_ref, fn state ->
      {:damage, type, Map.get(state.damage, type, 0) + delta}
    end)
  end

  @doc "Sets the current value of a simple tracker (clamped into its range)."
  def set(character, tracker_ref, value) when is_integer(value) do
    change(character, tracker_ref, fn _state -> {:value, value} end)
  end

  @doc "Sets the damage of a type (clamped so the total does not exceed the max)."
  def set_damage(character, tracker_ref, type, amount) when is_integer(amount) do
    change(character, tracker_ref, fn _state -> {:damage, type, amount} end)
  end

  @doc "A human readable message for the tracker errors."
  def error_message(:not_found), do: dgettext("domain", "That tracker does not exist.")

  def error_message(:invalid_damage_type),
    do: dgettext("domain", "That damage type does not exist.")

  def error_message(:damage_tracker),
    do: dgettext("domain", "This tracker tracks damage by type.")

  def error_message(:simple_tracker), do: dgettext("domain", "This tracker has no damage types.")
  def error_message(_), do: dgettext("domain", "The tracker could not be updated.")

  defp change(%Character{} = character, tracker_ref, fun) do
    case resolve(character, tracker_ref) do
      nil ->
        {:error, :not_found}

      tracker ->
        values = Characters.values_by_slug(character)
        Repo.transaction(fn -> do_change(character, tracker, values, fun) end)
    end
  end

  defp do_change(character, tracker, values, fun) do
    row = lock_row(character, tracker)
    state = build_state(tracker, row, values)

    case apply_change(tracker, state, fun.(state)) do
      {:ok, attrs} ->
        updated = row |> Ecto.Changeset.change(attrs) |> Repo.update!()
        build_state(tracker, updated, values)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp apply_change(%Tracker{damage_types: []}, state, {:value, value}),
    do: {:ok, %{value: clamp(value, 0, state.max)}}

  defp apply_change(%Tracker{damage_types: []}, _state, {:damage, _, _}),
    do: {:error, :simple_tracker}

  defp apply_change(%Tracker{}, _state, {:value, _}), do: {:error, :damage_tracker}

  defp apply_change(%Tracker{damage_types: types}, state, {:damage, type, amount}) do
    if type in types do
      others = state.total_damage - Map.get(state.damage, type, 0)
      amount = clamp(amount, 0, max(state.max - others, 0))
      {:ok, %{damage: Map.put(state.damage, type, amount)}}
    else
      {:error, :invalid_damage_type}
    end
  end

  defp lock_row(character, tracker) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      CharacterTracker,
      [
        %{
          character_id: character.id,
          tracker_id: tracker.id,
          damage: %{},
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:character_id, :tracker_id]
    )

    Repo.one!(
      from ct in CharacterTracker,
        where: ct.character_id == ^character.id and ct.tracker_id == ^tracker.id,
        lock: "FOR UPDATE"
    )
  end

  defp resolve(_character, %Tracker{} = tracker), do: tracker

  defp resolve(%Character{story_id: story_id}, slug) when is_binary(slug),
    do: Repo.get_by(Tracker, story_id: story_id, slug: slug)

  defp resolve(%Character{story_id: story_id}, id) when is_integer(id),
    do: Repo.get_by(Tracker, story_id: story_id, id: id)

  defp resolve(_, _), do: nil

  defp rows_by_tracker(_character, []), do: %{}

  defp rows_by_tracker(%Character{id: id}, tracker_ids) do
    Repo.all(
      from ct in CharacterTracker,
        where: ct.character_id == ^id and ct.tracker_id in ^tracker_ids
    )
    |> Map.new(&{&1.tracker_id, &1})
  end

  defp build_state(%Tracker{} = tracker, row, values) do
    {max, error} =
      case max_value(tracker, values) do
        {:ok, max} ->
          {max, nil}

        {:error, message} ->
          {0, dgettext("domain", "Invalid maximum: %{message}", message: message)}
      end

    stored = (row && row.damage) || %{}

    damage =
      Map.new(tracker.damage_types, fn type ->
        {type, stored |> Map.get(type, 0) |> to_int() |> clamp(0, max)}
      end)

    total = damage |> Map.values() |> Enum.sum() |> min(max)

    %{
      tracker: tracker,
      max: max,
      value: current_value(tracker, row, max, total),
      damage: damage,
      total_damage: total,
      remaining: max - total,
      error: error
    }
  end

  defp current_value(%Tracker{damage_types: [_ | _]}, _row, max, total), do: max - total

  defp current_value(_tracker, %{value: value}, max, _total) when is_integer(value),
    do: clamp(value, 0, max)

  defp current_value(%Tracker{starts_full: true}, _row, max, _total), do: max
  defp current_value(_tracker, _row, _max, _total), do: 0

  defp to_int(n) when is_integer(n), do: n
  defp to_int(_), do: 0

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
