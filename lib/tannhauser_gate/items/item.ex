defmodule TannhauserGate.Items.Item do
  @moduledoc """
  An item of a GDR's catalog: a name, a Markdown description, an optional
  image, a category, a base price and a few mechanics:

    * `slot`: when set the item can be equipped (one item per slot per
      character); its `modifiers` (`sheet item slug => ±N`) are added to the
      character's effective values while equipped;
    * `tracker_id` + `effect_change` (+ `effect_damage_type` for trackers with
      damage types): a consumable effect applied with
      `TannhauserGate.Trackers.adjust/3` when the item is used, consuming one
      unit when `consumed_on_use`;
    * `stackable`: non-stackable items are held one at a time per character.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_modifier 20

  schema "items" do
    field :name, :string
    field :description, :string
    field :image_path, :string
    field :category, :string
    field :price, :integer, default: 0
    field :stackable, :boolean, default: true
    field :slot, :string
    field :modifiers, :map, default: %{}
    field :effect_change, :integer
    field :effect_damage_type, :string
    field :consumed_on_use, :boolean, default: true

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :tracker, TannhauserGate.Trackers.Tracker

    timestamps(type: :utc_datetime)
  end

  @doc """
  `slugs` are the sheet item keys of the GDR (modifiers may only reference
  them); `trackers` the GDR's trackers (the effect may only reference them).
  """
  def changeset(item, attrs, slugs, trackers) do
    item
    |> cast(attrs, [
      :name,
      :description,
      :category,
      :price,
      :stackable,
      :slot,
      :tracker_id,
      :effect_change,
      :effect_damage_type,
      :consumed_on_use
    ])
    |> update_change(:name, &String.trim/1)
    |> update_change(:category, &trim_to_nil/1)
    |> update_change(:slot, &trim_to_nil/1)
    |> update_change(:effect_damage_type, &trim_to_nil/1)
    |> validate_required([:name, :price])
    |> validate_length(:name, max: 60)
    |> validate_length(:category, max: 40)
    |> validate_length(:slot, max: 40)
    |> validate_length(:description, max: 20_000)
    |> validate_number(:price, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000_000)
    |> cast_modifiers(attrs, slugs)
    |> validate_effect(trackers)
    |> unique_constraint(:name, name: :items_story_id_name_index)
    |> check_constraint(:price, name: :items_price_non_negative)
  end

  def image_changeset(item_or_changeset, path), do: change(item_or_changeset, image_path: path)

  @doc "Whether the item can be equipped."
  def equippable?(%__MODULE__{slot: slot}), do: is_binary(slot) and slot != ""

  @doc "Whether the item can be used (it has a tracker effect)."
  def usable?(%__MODULE__{tracker_id: id, effect_change: change}),
    do: not is_nil(id) and is_integer(change)

  defp validate_effect(changeset, trackers) do
    case get_field(changeset, :tracker_id) do
      nil ->
        changeset
        |> put_change(:effect_change, nil)
        |> put_change(:effect_damage_type, nil)

      tracker_id ->
        case Enum.find(trackers, &(&1.id == tracker_id)) do
          nil ->
            add_error(changeset, :tracker_id, "is not a tracker of this GDR")

          tracker ->
            changeset
            |> validate_required([:effect_change])
            |> validate_number(:effect_change,
              greater_than_or_equal_to: -1_000,
              less_than_or_equal_to: 1_000,
              not_equal_to: 0
            )
            |> validate_damage_type(tracker)
        end
    end
  end

  defp validate_damage_type(changeset, %{damage_types: []}),
    do: put_change(changeset, :effect_damage_type, nil)

  defp validate_damage_type(changeset, %{damage_types: types}) do
    changeset
    |> validate_required([:effect_damage_type],
      message: "choose the damage type (#{Enum.join(types, ", ")})"
    )
    |> validate_inclusion(:effect_damage_type, types,
      message: "is not a damage type of the tracker"
    )
  end

  defp cast_modifiers(changeset, attrs, slugs) do
    case fetch(attrs, :modifiers) do
      :error ->
        changeset

      {:ok, raw} when is_map(raw) ->
        {modifiers, changeset} =
          Enum.reduce(raw, {%{}, changeset}, &cast_modifier(&1, &2, slugs))

        put_change(changeset, :modifiers, modifiers)

      {:ok, _} ->
        add_error(changeset, :modifiers, "is invalid")
    end
  end

  defp cast_modifier({slug, value}, {acc, cs}, slugs) do
    slug = to_string(slug)

    case parse(value) do
      :blank ->
        {acc, cs}

      {:ok, 0} ->
        {acc, cs}

      {:ok, int} when abs(int) <= @max_modifier ->
        put_modifier(acc, cs, slug, int, slugs)

      {:ok, _} ->
        {acc,
         add_error(
           cs,
           :modifiers,
           "#{slug} must be between -#{@max_modifier} and #{@max_modifier}"
         )}

      :error ->
        {acc, add_error(cs, :modifiers, "#{slug} must be a whole number")}
    end
  end

  defp put_modifier(acc, cs, slug, int, slugs) do
    if slug in slugs,
      do: {Map.put(acc, slug, int), cs},
      else: {acc, add_error(cs, :modifiers, "references unknown sheet item #{slug}")}
  end

  defp fetch(attrs, key) do
    case Map.fetch(attrs, to_string(key)) do
      :error -> Map.fetch(attrs, key)
      found -> found
    end
  end

  defp parse(value) when is_integer(value), do: {:ok, value}
  defp parse(nil), do: :blank

  defp parse(value) when is_binary(value) do
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

  defp parse(_), do: :error

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
