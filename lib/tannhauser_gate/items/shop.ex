defmodule TannhauserGate.Items.Shop do
  @moduledoc "A shop of a GDR, optionally in one of its rooms, selling listed items."
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Items.Listing

  schema "shops" do
    field :name, :string
    field :description, :string

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :location, TannhauserGate.Stories.Location
    has_many :listings, Listing, preload_order: [asc: :position, asc: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(shop, attrs) do
    shop
    |> cast(attrs, [:name, :description, :location_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 20_000)
    |> unique_constraint(:name, name: :shops_story_id_name_index)
    |> foreign_key_constraint(:location_id)
  end
end
