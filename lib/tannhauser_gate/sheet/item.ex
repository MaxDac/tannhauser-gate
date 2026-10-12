defmodule TannhauserGate.Sheet.Item do
  @moduledoc """
  An attribute, skill or power defined by a game master for their GDR.
  Characters hold a numeric value between `min_value` and `max_value` for each.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Story

  @kinds ~w(attribute skill power)
  @slug_format ~r/^[a-z][a-z0-9_]{0,39}$/
  # Names used by formulas: functions and the XP cost variables.
  @reserved_slugs ~w(current next min max)

  schema "sheet_items" do
    field :kind, :string
    field :name, :string
    field :slug, :string
    field :description, :string
    field :min_value, :integer, default: 0
    field :max_value, :integer, default: 10
    field :position, :integer, default: 0

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def reserved_slugs, do: @reserved_slugs

  @doc """
  Derives a formula key from a name: "Blood Potency" becomes "blood_potency".
  """
  def slugify(name) when is_binary(name) do
    slug =
      name
      |> String.normalize(:nfd)
      |> String.replace(~r/[^\x00-\x7F]/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> String.slice(0, 40)

    cond do
      slug == "" -> "item"
      slug =~ ~r/^[0-9]/ -> String.slice("item_" <> slug, 0, 40)
      slug in @reserved_slugs -> slug <> "_item"
      true -> slug
    end
  end

  def slugify(_), do: nil

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:kind, :name, :slug, :description, :min_value, :max_value, :position])
    |> update_change(:name, &String.trim/1)
    |> update_change(:slug, &(&1 && &1 |> String.trim() |> String.downcase()))
    |> put_default_slug()
    |> validate_required([:kind, :name, :slug, :min_value, :max_value])
    |> validate_format(:slug, @slug_format,
      message: "must start with a letter and use only lowercase letters, digits and _"
    )
    |> validate_exclusion(:slug, @reserved_slugs, message: "is reserved")
    |> unique_constraint([:story_id, :slug],
      name: :sheet_items_story_id_slug_index,
      message: "is already used by another item"
    )
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_number(:min_value, greater_than_or_equal_to: -1_000, less_than_or_equal_to: 1_000)
    |> validate_number(:max_value, greater_than_or_equal_to: -1_000, less_than_or_equal_to: 1_000)
    |> validate_min_max()
    |> unique_constraint([:story_id, :kind, :name],
      name: :sheet_items_story_id_kind_name_index,
      message: "already exists"
    )
  end

  # The key stays stable when an item is renamed; it is only derived when blank.
  defp put_default_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when slug in [nil, ""] ->
        put_change(changeset, :slug, slugify(get_field(changeset, :name)))

      _ ->
        changeset
    end
  end

  defp validate_min_max(changeset) do
    min = get_field(changeset, :min_value)
    max = get_field(changeset, :max_value)

    if is_integer(min) and is_integer(max) and max < min do
      add_error(changeset, :max_value, "must be greater than or equal to the minimum")
    else
      changeset
    end
  end
end
