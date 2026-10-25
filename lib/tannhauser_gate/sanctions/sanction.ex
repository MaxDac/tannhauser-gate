defmodule TannhauserGate.Sanctions.Sanction do
  @moduledoc """
  A sanction issued by the masters of a GDR to a user: a `warning` (recorded
  and notified only), a `mute` (no posting) or a `ban` (no access). A nil
  `ends_at` makes a mute or ban permanent; a revoked sanction is no longer
  active. The table itself is the audit log.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User

  @kinds ~w(warning mute ban)

  schema "sanctions" do
    field :kind, :string
    field :reason, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :seen_at, :utc_datetime

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :user, User
    belongs_to :issued_by, User
    belongs_to :revoked_by, User
    belongs_to :report, TannhauserGate.Reports.Report

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc false
  def changeset(sanction, attrs) do
    sanction
    |> cast(attrs, [:kind, :reason, :starts_at, :ends_at])
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:kind, :reason, :starts_at])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:reason, max: 2_000)
    |> validate_ends_at()
  end

  defp validate_ends_at(changeset) do
    starts_at = get_field(changeset, :starts_at)

    validate_change(changeset, :ends_at, fn :ends_at, ends_at ->
      if starts_at && DateTime.compare(ends_at, starts_at) != :gt,
        do: [ends_at: "must be after the start"],
        else: []
    end)
  end

  @doc "Whether the sanction is in force at `now`: started, not ended and not revoked."
  def active?(%__MODULE__{} = sanction, now \\ DateTime.utc_now()) do
    is_nil(sanction.revoked_at) and DateTime.compare(sanction.starts_at, now) != :gt and
      (is_nil(sanction.ends_at) or DateTime.compare(sanction.ends_at, now) == :gt)
  end
end
