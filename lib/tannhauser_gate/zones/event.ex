defmodule TannhauserGate.Zones.Event do
  @moduledoc "An event posted by a master on a zone, visible to the players."
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Zones.Zone

  schema "zone_events" do
    field :title, :string
    field :body, :string
    field :happened_on, :date
    field :game_date_label, :string

    belongs_to :zone, Zone
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:title, :body, :happened_on, :game_date_label])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :body, :happened_on])
    |> validate_length(:title, max: 120)
    |> validate_length(:body, max: 10_000)
    |> validate_length(:game_date_label, max: 80)
  end
end
