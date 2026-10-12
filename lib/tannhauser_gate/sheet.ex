defmodule TannhauserGate.Sheet do
  @moduledoc """
  The character sheet definition of a GDR: attributes, skills and powers, all
  fully editable by the game master.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet.{Category, Item, Trait}
  alias TannhauserGate.Stories.Story

  def kinds, do: Item.kinds()

  def kind_label("attribute"), do: "Attributes"
  def kind_label("skill"), do: "Skills"
  def kind_label("power"), do: "Powers"

  @doc "All the sheet items of a story, ordered by position then name."
  def list_items(%Story{id: story_id}) do
    Repo.all(
      from i in Item,
        where: i.story_id == ^story_id,
        order_by: [asc: i.kind, asc: i.position, asc: i.name]
    )
  end

  @doc "The sheet items of a story grouped by kind (every kind is present)."
  def items_by_kind(%Story{} = story) do
    grouped = story |> list_items() |> Enum.group_by(& &1.kind)
    Map.new(Item.kinds(), &{&1, Map.get(grouped, &1, [])})
  end

  def get_item!(%Story{id: story_id}, id), do: Repo.get_by!(Item, id: id, story_id: story_id)

  def create_item(%Story{} = story, attrs) do
    %Item{story_id: story.id}
    |> Item.changeset(attrs)
    |> unique_default_slug(story)
    |> Repo.insert()
  end

  # A slug derived from the name gets a numeric suffix if already taken.
  defp unique_default_slug(changeset, story) do
    raw = Map.get(changeset.params || %{}, "slug")

    with true <- raw in [nil, ""],
         slug when is_binary(slug) <- Ecto.Changeset.get_field(changeset, :slug) do
      taken = MapSet.new(slugs(story))

      unique =
        Stream.iterate(1, &(&1 + 1))
        |> Stream.map(fn
          1 -> slug
          n -> String.slice(slug, 0, 36) <> "_#{n}"
        end)
        |> Enum.find(&(not MapSet.member?(taken, &1)))

      Ecto.Changeset.put_change(changeset, :slug, unique)
    else
      _ -> changeset
    end
  end

  @doc """
  Updates a sheet item. If its range shrinks, the characters' existing values
  are clamped into the new range so every sheet stays valid.
  """
  def update_item(%Item{} = item, attrs) do
    Repo.transaction(fn ->
      case item |> Item.changeset(attrs) |> Repo.update() do
        {:ok, updated} ->
          clamp_traits(updated)
          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp clamp_traits(%Item{id: id, min_value: min, max_value: max}) do
    Repo.update_all(
      from(t in Trait,
        where: t.sheet_item_id == ^id and (t.value < ^min or t.value > ^max),
        update: [set: [value: fragment("LEAST(GREATEST(?, ?), ?)", t.value, ^min, ^max)]]
      ),
      []
    )
  end

  def delete_item(%Item{} = item), do: Repo.delete(item)

  def change_item(%Item{} = item, attrs \\ %{}), do: Item.changeset(item, attrs)

  @doc "The formula keys (slugs) of every item of a story."
  def slugs(%Story{id: story_id}) do
    Repo.all(from i in Item, where: i.story_id == ^story_id, select: i.slug, order_by: i.slug)
  end

  # -- Categories: creation budgets and XP costs ------------------------------

  @doc """
  The configuration of every sheet category of a story, as a map
  `kind => %Category{}`. Unconfigured categories get a default (free, no XP
  cost) unsaved struct.
  """
  def categories(%Story{id: story_id}) do
    saved =
      Repo.all(from c in Category, where: c.story_id == ^story_id) |> Map.new(&{&1.kind, &1})

    Map.new(Item.kinds(), &{&1, Map.get(saved, &1, %Category{story_id: story_id, kind: &1})})
  end

  def get_category(%Story{} = story, kind), do: Map.fetch!(categories(story), kind)

  def change_category(%Category{} = category, attrs \\ %{}, slugs \\ []),
    do: Category.changeset(category, attrs, slugs)

  @doc "Creates or updates the configuration of a sheet category."
  def save_category(%Story{} = story, kind, attrs) when kind in ["attribute", "skill", "power"] do
    story
    |> get_category(kind)
    |> Category.changeset(attrs, slugs(story))
    |> Repo.insert_or_update()
  end

  @doc """
  The value an item gets on a new character: the category starting value
  (clamped into the item range) when the category has a creation budget,
  the item minimum otherwise.
  """
  def default_value(%Item{} = item, %Category{} = category) do
    if Category.budgeted?(category),
      do: clamp(category.starting_value, item.min_value, item.max_value),
      else: item.min_value
  end

  @doc """
  Fills every missing item of `items_by_kind` with its default value.
  `values` maps item ids to integers.
  """
  def with_defaults(values, items_by_kind, categories) do
    Enum.reduce(items_by_kind, values, fn {kind, items}, acc ->
      Enum.reduce(items, acc, fn item, acc ->
        Map.put_new(acc, item.id, default_value(item, Map.fetch!(categories, kind)))
      end)
    end)
  end

  @doc """
  The creation budget status of one category for the given values
  (`item_id => integer`), used both to validate and to guide players:

    * `%{mode: "free"}`
    * `%{mode: "points", total: n, spent: n, remaining: n, ok?: bool}`
    * `%{mode: "distribution", expected: [n], assigned: [n], missing: [n],
       extra: [n], ok?: bool}`
  """
  def budget_status(%Category{creation_mode: "points"} = category, items, values) do
    total = category.creation_points || 0

    spent =
      Enum.reduce(items, 0, fn item, acc ->
        acc + (value_of(values, item) - default_value(item, category))
      end)

    below = Enum.any?(items, &(value_of(values, &1) < default_value(&1, category)))

    %{
      mode: "points",
      total: total,
      spent: spent,
      remaining: total - spent,
      below_start?: below,
      ok?: spent <= total and not below
    }
  end

  def budget_status(%Category{creation_mode: "distribution"} = category, items, values) do
    distribution = Category.distribution(category)
    padding = max(length(items) - length(distribution), 0)
    expected = Enum.sort(distribution ++ List.duplicate(category.starting_value, padding), :desc)
    assigned = items |> Enum.map(&value_of(values, &1)) |> Enum.sort(:desc)

    %{
      mode: "distribution",
      distribution: distribution,
      expected: expected,
      assigned: assigned,
      missing: expected -- assigned,
      extra: assigned -- expected,
      too_many?: length(distribution) > length(items),
      ok?: length(distribution) <= length(items) and assigned == expected
    }
  end

  def budget_status(%Category{}, _items, _values), do: %{mode: "free", ok?: true}

  @doc """
  Checks complete creation values (`item_id => integer`) against the budgets
  of the given kinds. Returns a list of `{kind, message}` errors.
  """
  def creation_errors(items_by_kind, categories, values, kinds \\ Item.kinds()) do
    Enum.flat_map(kinds, fn kind ->
      items = Map.get(items_by_kind, kind, [])

      categories
      |> Map.fetch!(kind)
      |> budget_status(items, values)
      |> budget_errors(kind)
    end)
  end

  defp budget_errors(%{ok?: true}, _kind), do: []

  defp budget_errors(%{mode: "points"} = status, kind) do
    label = String.downcase(kind_label(kind))

    cond do
      status.below_start? ->
        [{kind, "#{label} cannot go below their starting value"}]

      true ->
        [{kind, "#{label} use #{status.spent} points but only #{status.total} are available"}]
    end
  end

  defp budget_errors(%{mode: "distribution"} = status, kind) do
    label = String.downcase(kind_label(kind))

    if status.too_many? do
      [{kind, "#{label} distribution has more values than there are items"}]
    else
      [{kind, "#{label} must use exactly the values #{Enum.join(status.expected, ", ")}"}]
    end
  end

  defp value_of(values, %Item{id: id, min_value: min}), do: Map.get(values, id, min)

  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
