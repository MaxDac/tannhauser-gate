defmodule TannhauserGate.Trackers.Tracker do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A per-GDR resource tracked on every character (e.g. Health, Willpower,
  Hunger). Its maximum is a formula over the sheet item keys (or a fixed
  number); it can optionally track damage of several types (e.g.
  superficial/aggravated) instead of a simple current value.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Formula
  alias TannhauserGate.Sheet.Item
  alias TannhauserGate.Stories.Story

  schema "trackers" do
    field :name, :string
    field :slug, :string
    field :max_formula, :string
    field :damage_types, {:array, :string}, default: []
    field :starts_full, :boolean, default: true
    field :public, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  @doc """
  `slugs` are the sheet item keys the max formula may reference.
  `damage_types` can be given as a list or a comma separated string.
  """
  def changeset(tracker, attrs, slugs \\ []) do
    attrs = normalize_damage_types(attrs)

    tracker
    |> cast(attrs, [:name, :slug, :max_formula, :damage_types, :starts_full, :public, :position])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:max_formula, &(&1 && String.trim(&1)))
    |> update_change(:slug, &(&1 && &1 |> String.trim() |> String.downcase()))
    |> put_default_slug()
    |> validate_required([:name, :slug, :max_formula])
    |> validate_length(:name, max: 60)
    |> validate_length(:max_formula, max: 200)
    |> validate_format(:slug, ~r/^[a-z][a-z0-9_]{0,39}$/,
      message:
        dgettext_noop(
          "errors",
          "must start with a letter and use only lowercase letters, digits and _"
        )
    )
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> validate_damage_types()
    |> Formula.validate_formula(:max_formula, slugs)
    |> unique_constraint([:story_id, :slug],
      name: :trackers_story_id_slug_index,
      message: dgettext_noop("errors", "is already used by another tracker")
    )
  end

  defp normalize_damage_types(%{} = attrs) do
    Map.new(attrs, fn
      {key, value} when key in [:damage_types, "damage_types"] and is_binary(value) ->
        {key, value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))}

      pair ->
        pair
    end)
  end

  defp put_default_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when slug in [nil, ""] ->
        put_change(changeset, :slug, Item.slugify(get_field(changeset, :name)))

      _ ->
        changeset
    end
  end

  defp validate_damage_types(changeset) do
    validate_change(changeset, :damage_types, fn :damage_types, types ->
      cond do
        length(types) > 5 ->
          [damage_types: dgettext_noop("errors", "can be at most 5")]

        Enum.any?(types, &(String.length(&1) > 30)) ->
          [damage_types: dgettext_noop("errors", "names must be short")]

        length(Enum.uniq(types)) != length(types) ->
          [damage_types: dgettext_noop("errors", "must be distinct")]

        true ->
          []
      end
    end)
  end
end
