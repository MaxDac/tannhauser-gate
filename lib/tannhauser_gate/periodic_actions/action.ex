defmodule TannhauserGate.PeriodicActions.Action do
  @moduledoc """
  A periodic (hunt-like) action configured by the GDR admin: a dice pool of
  sheet items rolled against a difficulty taken from a zone property
  (`difficulty_source: "zone"`) or from a per-character value set by the
  masters (`"character"`), with a tracker effect on success and on failure,
  and a cooldown in hours.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Story

  @sources ~w(zone character)

  schema "periodic_actions" do
    field :name, :string
    field :description, :string
    field :items, {:array, :string}, default: []
    field :difficulty_source, :string, default: "zone"
    field :zone_property, :string
    field :default_difficulty, :integer, default: 1
    field :success_tracker, :string
    field :success_damage_type, :string
    field :success_delta, :integer, default: 0
    field :failure_tracker, :string
    field :failure_damage_type, :string
    field :failure_delta, :integer, default: 0
    field :cooldown_hours, :integer, default: 24
    field :position, :integer, default: 0

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  def sources, do: @sources

  @doc """
  `context` holds what the action may reference: `:items` (sheet item
  slugs), `:trackers` (tracker structs) and `:properties` (zone property
  slugs). `items` can be given as a list or a comma separated string.
  """
  def changeset(action, attrs, context) do
    action
    |> cast(normalize_items(attrs), [
      :name,
      :description,
      :items,
      :difficulty_source,
      :zone_property,
      :default_difficulty,
      :success_tracker,
      :success_damage_type,
      :success_delta,
      :failure_tracker,
      :failure_damage_type,
      :failure_delta,
      :cooldown_hours,
      :position
    ])
    |> update_change(:name, &String.trim/1)
    |> validate_required([
      :name,
      :items,
      :difficulty_source,
      :default_difficulty,
      :cooldown_hours
    ])
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 2_000)
    |> validate_inclusion(:difficulty_source, @sources)
    |> validate_number(:default_difficulty,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_number(:cooldown_hours, greater_than_or_equal_to: 0, less_than_or_equal_to: 720)
    |> validate_number(:success_delta, greater_than_or_equal_to: -100, less_than_or_equal_to: 100)
    |> validate_number(:failure_delta, greater_than_or_equal_to: -100, less_than_or_equal_to: 100)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> validate_items(Map.get(context, :items, []))
    |> validate_zone_property(Map.get(context, :properties, []))
    |> validate_effect(:success, Map.get(context, :trackers, []))
    |> validate_effect(:failure, Map.get(context, :trackers, []))
    |> unique_constraint([:story_id, :name],
      error_key: :name,
      name: :periodic_actions_story_id_name_index,
      message: "is already used by another action"
    )
  end

  defp normalize_items(%{} = attrs) do
    Map.new(attrs, fn
      {key, value} when key in [:items, "items"] and is_binary(value) ->
        {key, value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))}

      {key, value} when key in [:items, "items"] and is_list(value) ->
        {key, Enum.reject(value, &(&1 in [nil, ""]))}

      pair ->
        pair
    end)
  end

  defp validate_items(changeset, slugs) do
    validate_change(changeset, :items, fn :items, items ->
      cond do
        items == [] ->
          [items: "can't be blank"]

        length(items) > 10 ->
          [items: "can be at most 10"]

        Enum.all?(items, &(&1 in slugs)) ->
          []

        true ->
          [
            items:
              "must be sheet item keys (#{Enum.reject(items, &(&1 in slugs)) |> Enum.join(", ")} unknown)"
          ]
      end
    end)
  end

  defp validate_zone_property(changeset, properties) do
    if get_field(changeset, :difficulty_source) == "zone" do
      changeset
      |> validate_required([:zone_property],
        message: "is required when the difficulty comes from the zone"
      )
      |> validate_inclusion(:zone_property, properties, message: "is not a zone property")
    else
      put_change(changeset, :zone_property, nil)
    end
  end

  defp validate_effect(changeset, kind, trackers) do
    tracker_field = :"#{kind}_tracker"
    type_field = :"#{kind}_damage_type"

    case get_field(changeset, tracker_field) do
      slug when slug in [nil, ""] ->
        changeset |> put_change(tracker_field, nil) |> put_change(type_field, nil)

      slug ->
        case Enum.find(trackers, &(&1.slug == slug)) do
          nil -> add_error(changeset, tracker_field, "is not a tracker")
          tracker -> validate_damage_type(changeset, type_field, tracker.damage_types)
        end
    end
  end

  defp validate_damage_type(changeset, field, []), do: put_change(changeset, field, nil)

  defp validate_damage_type(changeset, field, types) do
    changeset
    |> validate_required([field], message: "is required for this tracker")
    |> validate_inclusion(field, types)
  end
end
