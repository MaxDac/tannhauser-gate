defmodule TannhauserGate.Quests.Quest do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A quest (or scene) recorded by a master: title, Markdown summary, the date
  it was held, the room, the master who ran it and its visibility (`public`
  or `masters` only). An optional chat-log range (`log_from`/`log_to` in the
  quest's room) links to the master chat log.

  `rewards_applied_at` is set once the participants' rewards were handed out
  (`TannhauserGate.Quests.apply_rewards/3`); after that the participants and
  their rewards are frozen.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @visibilities ~w(public masters)

  def visibilities, do: @visibilities

  schema "quests" do
    field :title, :string
    field :summary, :string
    field :held_on, :date
    field :game_date_label, :string
    field :visibility, :string, default: "public"
    field :log_from, :utc_datetime
    field :log_to, :utc_datetime
    field :rewards_applied_at, :utc_datetime

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :location, TannhauserGate.Stories.Location
    belongs_to :master, TannhauserGate.Accounts.User
    belongs_to :rewards_applied_by, TannhauserGate.Accounts.User

    has_many :participants, TannhauserGate.Quests.Participant

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for the editable fields; `location_id` is checked by `TannhauserGate.Quests`."
  def changeset(quest, attrs) do
    quest
    |> cast(attrs, [
      :title,
      :summary,
      :held_on,
      :game_date_label,
      :visibility,
      :location_id,
      :log_from,
      :log_to
    ])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :held_on, :visibility])
    |> validate_length(:title, max: 120)
    |> validate_length(:summary, max: 20_000)
    |> validate_length(:game_date_label, max: 80)
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_range()
  end

  defp validate_range(changeset) do
    from = get_field(changeset, :log_from)
    to = get_field(changeset, :log_to)

    if from && to && DateTime.compare(from, to) == :gt,
      do: add_error(changeset, :log_to, dgettext_noop("errors", "must be after the start")),
      else: changeset
  end

  @doc "Whether the rewards were already handed out."
  def rewarded?(%__MODULE__{rewards_applied_at: at}), do: not is_nil(at)
end
