defmodule TannhauserGate.Sheet do
  @moduledoc """
  The character sheet definition of a GDR: attributes, skills and powers, all
  fully editable by the game master.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet.{Item, Trait}
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
    |> Repo.insert()
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
end
