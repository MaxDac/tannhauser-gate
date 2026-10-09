defmodule TannhauserGate.Characters do
  @moduledoc """
  Player characters. Each character belongs to a user and to a story (GDR), and
  a user can have only one character per GDR. Its attributes, skills and powers
  are numeric values for the sheet items defined by the game master.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TannhauserGate.Accounts
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet.{Item, Trait}

  def list_characters do
    Repo.all(
      from c in Character,
        order_by: [asc: c.name, asc: c.id],
        preload: [:user, :story]
    )
  end

  def list_story_characters(story_id) do
    Repo.all(
      from c in Character,
        where: c.story_id == ^story_id,
        order_by: [asc: c.name, asc: c.id],
        preload: [:user, :job]
    )
  end

  def list_user_characters(%User{id: user_id}, story_id \\ nil) do
    query =
      from c in Character,
        where: c.user_id == ^user_id,
        order_by: [asc: c.name, asc: c.id],
        preload: [:story]

    query = if story_id, do: where(query, [c], c.story_id == ^story_id), else: query

    Repo.all(query)
  end

  @doc "The (single) character of the user in the given story, if any."
  def get_user_story_character(%User{id: user_id}, story_id) do
    Repo.get_by(Character, user_id: user_id, story_id: story_id)
  end

  def get_character!(id),
    do: Character |> Repo.get!(id) |> Repo.preload([:user, :story, :job])

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
  Creates a character owned by `user`. `attrs["traits"]` maps sheet item ids to
  values. `avatar_path` (optional) is the public path of an already stored
  avatar image.
  """
  def create_character(%User{} = user, attrs, avatar_path \\ nil) do
    changeset =
      %Character{user_id: user.id}
      |> Character.changeset(attrs)
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

  def update_character(%Character{} = character, attrs, avatar_path \\ nil) do
    changeset =
      character
      |> Character.changeset(attrs)
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

  def change_character(%Character{} = character, attrs \\ %{}),
    do: character |> Character.changeset(attrs) |> validate_traits(attrs)

  @doc """
  Owners, admins and the game master of the character's GDR can edit a character.
  """
  def can_edit?(%User{} = user, %Character{} = character) do
    character.user_id == user.id or Accounts.admin?(user) or gm_of?(user, character)
  end

  def can_edit?(_, _), do: false

  defp gm_of?(%User{id: user_id} = user, %Character{story_id: story_id}) do
    Accounts.gm?(user) and
      Repo.exists?(
        from s in TannhauserGate.Stories.Story,
          where: s.id == ^story_id and s.owner_id == ^user_id
      )
  end

  ## Traits

  defp validate_traits(changeset, attrs) do
    params = attrs["traits"] || attrs[:traits]
    story_id = Ecto.Changeset.get_field(changeset, :story_id)

    if is_map(params) and is_integer(story_id) do
      items = Repo.all(from i in Item, where: i.story_id == ^story_id)

      Enum.reduce(items, changeset, fn item, cs ->
        case fetch_param(params, item.id) do
          :error -> cs
          {:ok, raw} -> check_trait(cs, item, raw)
        end
      end)
    else
      changeset
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
