defmodule TannhauserGate.Esiti.Esito do
  @moduledoc """
  An esito ("outcome") request: a player character asks the masters to
  resolve an action off the chat (an investigation, a craft, a contact...).

  Statuses: `open` (waiting for a master), `claimed` (a master took it),
  `resolved` (the outcome was published, with its dice result and applied
  effects) and `closed` (withdrawn by the player or dismissed by a master).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(open claimed resolved closed)
  @active ~w(open claimed)

  def statuses, do: @statuses
  def active_statuses, do: @active

  schema "esiti" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "open"
    field :claimed_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :outcome, :string
    field :dice_result, :map
    field :effects, :map
    field :game_date_label, :string

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :user, TannhauserGate.Accounts.User
    belongs_to :location, TannhauserGate.Stories.Location
    belongs_to :zone, TannhauserGate.Zones.Zone
    belongs_to :claimed_by, TannhauserGate.Accounts.User
    belongs_to :resolved_by, TannhauserGate.Accounts.User

    many_to_many :related_characters, TannhauserGate.Characters.Character,
      join_through: "esito_characters",
      preload_order: [asc: :name]

    has_many :messages, TannhauserGate.Esiti.Message, preload_order: [asc: :inserted_at, asc: :id]

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for a new request (title and body; the rest is set by `TannhauserGate.Esiti`)."
  def changeset(esito, attrs) do
    esito
    |> cast(attrs, [:title, :body])
    |> update_change(:title, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:title, :body])
    |> validate_length(:title, max: 120)
    |> validate_length(:body, max: 10_000)
  end

  @doc "Whether the esito is still waiting for an outcome."
  def active?(%__MODULE__{status: status}), do: status in @active
end
