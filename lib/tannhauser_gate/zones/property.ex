defmodule TannhauserGate.Zones.Property do
  @moduledoc """
  A numeric property every zone of a GDR carries (e.g. danger, resonance).
  Non-public properties are only shown to masters.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Sheet.Item
  alias TannhauserGate.Stories.Story

  schema "zone_properties" do
    field :name, :string
    field :slug, :string
    field :default_value, :integer, default: 0
    field :public, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(property, attrs) do
    property
    |> cast(attrs, [:name, :slug, :default_value, :public, :position])
    |> update_change(:name, &String.trim/1)
    |> update_change(:slug, &(&1 |> String.trim() |> String.downcase()))
    |> put_default_slug()
    |> validate_required([:name, :slug, :default_value])
    |> validate_length(:name, max: 60)
    |> validate_format(:slug, ~r/^[a-z][a-z0-9_]{0,39}$/,
      message: "must start with a letter and use only lowercase letters, digits and _"
    )
    |> validate_number(:default_value,
      greater_than_or_equal_to: -1_000,
      less_than_or_equal_to: 1_000
    )
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> unique_constraint([:story_id, :slug],
      error_key: :slug,
      name: :zone_properties_story_id_slug_index,
      message: "is already used by another property"
    )
  end

  defp put_default_slug(changeset) do
    name = get_field(changeset, :name)

    if get_field(changeset, :slug) in [nil, ""] and is_binary(name) and name != "",
      do: put_change(changeset, :slug, Item.slugify(name)),
      else: changeset
  end
end
