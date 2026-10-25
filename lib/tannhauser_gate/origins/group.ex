defmodule TannhauserGate.Origins.Group do
  @moduledoc "An origin group of a GDR (e.g. \"Race\", \"Class\"): characters pick one of its options."
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Origins.Option

  schema "origin_groups" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0
    field :required, :boolean, default: false

    belongs_to :story, TannhauserGate.Stories.Story
    has_many :options, Option, preload_order: [asc: :position, asc: :name]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :description, :position, :required])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 2_000)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> unique_constraint(:name, name: :origin_groups_story_id_name_index)
  end
end
