defmodule TannhauserGate.Origins do
  @moduledoc """
  Origins (races & classes), the `:origins` optional module.

  The GDR admin defines origin groups (e.g. "Race", "Class"), some of them
  required, each with options carrying a Markdown description, an optional
  image and sheet bonuses (`sheet item slug => ±N`). A character picks one
  option per group: owners only until approval (like trait values), masters
  at any time.

  The bonuses are added to the trait values wherever they feed mechanics
  (formulas, tracker maximums, dice pools, periodic actions) through
  `TannhauserGate.Characters.values_by_slug/1`; creation budgets and XP costs
  keep using the base values. The effective value may exceed the item
  maximum by the bonus.

  Options flagged `requires_approval` can be picked by players, but they are
  highlighted to the masters in the approval queue: approving the character
  approves its origins.

  Everything is a no-op (no bonuses, no choices saved) when the module is
  disabled for the GDR. This context performs no permission checks.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Origins.{CharacterOrigin, Group, Option}
  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  @doc "Whether the origins module is enabled for the story (or story id)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :origins)
  def enabled?(story_id) when is_integer(story_id), do: enabled?(Stories.get_story(story_id))
  def enabled?(_), do: false

  ## Groups

  @doc "The origin groups of a story with their options, in order."
  def list_groups(%Story{id: story_id}) do
    Repo.all(
      from g in Group,
        where: g.story_id == ^story_id,
        order_by: [asc: g.position, asc: g.name],
        preload: :options
    )
  end

  def get_group!(%Story{id: story_id}, id), do: Repo.get_by!(Group, id: id, story_id: story_id)

  def create_group(%Story{} = story, attrs),
    do: %Group{story_id: story.id} |> Group.changeset(attrs) |> Repo.insert()

  def update_group(%Group{} = group, attrs), do: group |> Group.changeset(attrs) |> Repo.update()

  @doc "Deletes a group with its options and the characters' choices in it."
  def delete_group(%Group{} = group), do: Repo.delete(group)

  def change_group(%Group{} = group, attrs \\ %{}), do: Group.changeset(group, attrs)

  ## Options

  @doc "An option of the story; raises if it belongs to another story."
  def get_option!(%Story{id: story_id}, id), do: Repo.get_by!(Option, id: id, story_id: story_id)

  @doc """
  Creates an option; its group must belong to the story and its bonuses must
  reference the story's sheet items. `image_path` is an already stored image.
  """
  def create_option(%Story{} = story, attrs, image_path \\ nil) do
    %Option{story_id: story.id}
    |> Option.changeset(attrs, Sheet.slugs(story))
    |> validate_group(story)
    |> maybe_put_image(image_path)
    |> Repo.insert()
  end

  def update_option(%Story{} = story, %Option{} = option, attrs, image_path \\ nil) do
    option
    |> Option.changeset(attrs, Sheet.slugs(story))
    |> validate_group(story)
    |> maybe_put_image(image_path)
    |> Repo.update()
  end

  def delete_option(%Option{} = option), do: Repo.delete(option)

  def change_option(%Story{} = story, %Option{} = option, attrs \\ %{}),
    do: Option.changeset(option, attrs, Sheet.slugs(story))

  @doc "Removes the image of an option."
  def remove_option_image(%Option{} = option),
    do: option |> Option.image_changeset(nil) |> Repo.update()

  defp maybe_put_image(changeset, nil), do: changeset
  defp maybe_put_image(changeset, path), do: Option.image_changeset(changeset, path)

  defp validate_group(changeset, %Story{id: story_id}) do
    group_id = Ecto.Changeset.get_field(changeset, :group_id)

    if is_nil(group_id) or
         Repo.exists?(from g in Group, where: g.id == ^group_id and g.story_id == ^story_id),
       do: changeset,
       else: Ecto.Changeset.add_error(changeset, :group_id, "is not an origin group of this GDR")
  end

  ## Character choices

  @doc """
  The origins of a character as `[%{group: group, option: option}]`, in
  group order (empty when the module is disabled).
  """
  def character_origins(%Character{id: nil}), do: []

  def character_origins(%Character{} = character) do
    if enabled?(story_of(character)) do
      Repo.all(
        from co in CharacterOrigin,
          join: g in assoc(co, :origin_group),
          join: o in assoc(co, :origin_option),
          where: co.character_id == ^character.id,
          order_by: [asc: g.position, asc: g.name],
          select: %{group: g, option: o}
      )
    else
      []
    end
  end

  @doc "The origins of many characters: `%{character_id => [option]}`."
  def origins_by_character(%Story{} = story, character_ids) do
    if enabled?(story) do
      Repo.all(
        from co in CharacterOrigin,
          join: g in assoc(co, :origin_group),
          join: o in assoc(co, :origin_option),
          where: co.character_id in ^character_ids and g.story_id == ^story.id,
          order_by: [asc: g.position, asc: g.name],
          select: {co.character_id, o}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    else
      %{}
    end
  end

  @doc "The chosen option id of every group: `%{group_id => option_id}`."
  def choices(%Character{id: nil}), do: %{}

  def choices(%Character{id: id}) do
    Repo.all(
      from co in CharacterOrigin,
        where: co.character_id == ^id,
        select: {co.origin_group_id, co.origin_option_id}
    )
    |> Map.new()
  end

  @doc """
  Normalizes submitted choices (`%{group_id => option_id | ""}`, string or
  integer keys and values) against the groups of the story. Returns
  `{:ok, %{group_id => option_id | nil}}` or `{:error, message}` when an option
  does not belong to its group (or the GDR). Unknown groups are an error too.
  """
  def normalize_choices(groups, params) when is_map(params) do
    by_id = Map.new(groups, &{&1.id, &1})

    Enum.reduce_while(params, {:ok, %{}}, fn {raw_group, raw_option}, {:ok, acc} ->
      with {:ok, group_id} <- parse_id(raw_group),
           %Group{} = group <- by_id[group_id] do
        normalize_choice(group, parse_id(raw_option), acc)
      else
        _ -> {:halt, {:error, "Unknown origin group"}}
      end
    end)
  end

  def normalize_choices(_groups, _params), do: {:error, "Invalid origins"}

  defp normalize_choice(group, :blank, acc), do: {:cont, {:ok, Map.put(acc, group.id, nil)}}

  defp normalize_choice(group, {:ok, option_id}, acc) do
    if Enum.any?(group.options, &(&1.id == option_id)),
      do: {:cont, {:ok, Map.put(acc, group.id, option_id)}},
      else: {:halt, {:error, "#{group.name}: choose one of its options"}}
  end

  defp normalize_choice(group, :error, _acc),
    do: {:halt, {:error, "#{group.name}: choose one of its options"}}

  @doc "The required groups without a choice in `choices` (`%{group_id => option_id}`)."
  def missing_required(groups, choices) do
    Enum.filter(groups, &(&1.required and is_nil(Map.get(choices, &1.id))))
  end

  @doc """
  The required groups of the character's GDR it has not chosen yet (empty
  when the module is disabled).
  """
  def missing_required(%Character{} = character) do
    story = story_of(character)

    if enabled?(story),
      do: story |> list_groups() |> missing_required(choices(character)),
      else: []
  end

  @doc """
  Ecto validation used by `TannhauserGate.Characters`: checks `attrs["origins"]`
  (when present and the module is enabled) against the groups of the
  changeset's GDR, adding errors on `:origins`.
  """
  def validate_choices(changeset, attrs) do
    params = attrs["origins"]
    story_id = Ecto.Changeset.get_field(changeset, :story_id)

    with true <- is_map(params),
         true <- is_integer(story_id),
         %Story{} = story <- Stories.get_story(story_id),
         true <- enabled?(story),
         {:error, message} <- normalize_choices(list_groups(story), params) do
      Ecto.Changeset.add_error(changeset, :origins, message)
    else
      _ -> changeset
    end
  end

  @doc """
  Saves the submitted choices (`%{group_id => option_id | ""}`) of a character
  within a transaction (`repo`); blank values clear the group. A no-op when
  the module is disabled. Options are checked against their group and GDR.
  """
  def save_choices(repo \\ Repo, %Character{} = character, params) do
    story = story_of(character)

    if is_map(params) and enabled?(story) do
      case normalize_choices(list_groups(story), params) do
        {:ok, choices} -> {:ok, write_choices(repo, character, choices)}
        {:error, message} -> {:error, message}
      end
    else
      {:ok, 0}
    end
  end

  defp write_choices(repo, character, choices) do
    {cleared, chosen} = Enum.split_with(choices, fn {_g, o} -> is_nil(o) end)
    cleared_ids = Enum.map(cleared, &elem(&1, 0))

    repo.delete_all(
      from co in CharacterOrigin,
        where: co.character_id == ^character.id and co.origin_group_id in ^cleared_ids
    )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      for {group_id, option_id} <- chosen,
          do: %{
            character_id: character.id,
            origin_group_id: group_id,
            origin_option_id: option_id,
            inserted_at: now,
            updated_at: now
          }

    {count, _} =
      repo.insert_all(CharacterOrigin, rows,
        on_conflict: {:replace, [:origin_option_id, :updated_at]},
        conflict_target: [:character_id, :origin_group_id]
      )

    count + length(cleared)
  end

  ## Bonuses

  @doc """
  The total origin bonus of a character per sheet item slug
  (`%{slug => ±N}`); empty when the module is disabled.
  """
  def bonuses(%Character{id: nil}), do: %{}

  def bonuses(%Character{} = character) do
    if enabled?(story_of(character)) do
      Repo.all(
        from co in CharacterOrigin,
          join: o in assoc(co, :origin_option),
          where: co.character_id == ^character.id,
          select: o.bonuses
      )
      |> sum_bonuses()
    else
      %{}
    end
  end

  @doc "Sums bonus maps (`[%{slug => n}]`) into one."
  def sum_bonuses(bonus_maps) do
    Enum.reduce(bonus_maps, %{}, fn bonuses, acc ->
      Enum.reduce(bonuses || %{}, acc, fn
        {slug, n}, acc when is_integer(n) -> Map.update(acc, slug, n, &(&1 + n))
        _, acc -> acc
      end)
    end)
  end

  @doc "Applies `bonuses` (`%{slug => n}`) to `values` (`%{slug => n}`), only for existing slugs."
  def apply_bonuses(values, bonuses) do
    Enum.reduce(bonuses, values, fn {slug, n}, acc ->
      if Map.has_key?(acc, slug), do: Map.update!(acc, slug, &(&1 + n)), else: acc
    end)
  end

  @doc "Whether the character picked an option that requires the masters' approval."
  def requires_approval?(%Character{} = character) do
    Enum.any?(character_origins(character), & &1.option.requires_approval)
  end

  @doc "A short human label for a bonus map, e.g. `\"+1 body, −1 empathy\"`."
  def bonus_label(bonuses) when map_size(bonuses) == 0, do: nil

  def bonus_label(bonuses) do
    bonuses
    |> Enum.sort()
    |> Enum.map_join(", ", fn {slug, n} -> "#{signed(n)} #{slug}" end)
  end

  @doc "An integer with its sign (`+1`, `−2`, `0`)."
  def signed(n) when n > 0, do: "+#{n}"
  def signed(n) when n < 0, do: "−#{abs(n)}"
  def signed(0), do: "0"

  defp parse_id(value) when is_integer(value), do: {:ok, value}
  defp parse_id(nil), do: :blank

  defp parse_id(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        :blank

      trimmed ->
        case Integer.parse(trimmed) do
          {int, ""} -> {:ok, int}
          _ -> :error
        end
    end
  end

  defp parse_id(_), do: :error

  defp story_of(%Character{story: %Story{} = story}), do: story
  defp story_of(%Character{story_id: story_id}), do: Stories.get_story(story_id)
end
