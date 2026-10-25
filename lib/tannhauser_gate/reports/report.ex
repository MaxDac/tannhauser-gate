defmodule TannhauserGate.Reports.Report do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A report filed by a member of a GDR about a piece of content (a chat entry,
  a forum post, a letter, a notice) or a character. The reported text is
  snapshotted, since the content may be deleted later. The masters resolve or
  dismiss it with notes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User

  @target_types ~w(chat forum_post mail notice character)
  @categories ~w(harassment spam metagame rules other)
  @statuses ~w(open resolved dismissed)

  schema "reports" do
    field :target_type, :string
    field :target_id, :integer
    field :target_label, :string
    field :content_snapshot, :string
    field :category, :string
    field :reason, :string
    field :status, :string, default: "open"
    field :resolution_notes, :string
    field :content_deleted, :boolean, default: false
    field :handled_at, :utc_datetime

    belongs_to :story, TannhauserGate.Stories.Story
    belongs_to :reporter, User
    belongs_to :target_user, User
    belongs_to :handled_by, User

    timestamps(type: :utc_datetime)
  end

  def target_types, do: @target_types
  def categories, do: @categories
  def statuses, do: @statuses

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:category, :reason])
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:category])
    |> validate_inclusion(:category, @categories)
    |> validate_length(:reason, max: 2_000)
    |> unique_constraint([:reporter_id, :target_type, :target_id],
      name: :reports_one_open_per_target_index,
      message: dgettext_noop("errors", "you already reported this and the masters are on it")
    )
  end

  @doc false
  def resolution_changeset(report, attrs) do
    report
    |> cast(attrs, [:status, :resolution_notes])
    |> update_change(:resolution_notes, &String.trim/1)
    |> validate_required([:status])
    |> validate_inclusion(:status, ~w(resolved dismissed))
    |> validate_length(:resolution_notes, max: 2_000)
  end
end
