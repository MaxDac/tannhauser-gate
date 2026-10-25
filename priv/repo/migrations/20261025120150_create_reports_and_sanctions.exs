defmodule TannhauserGate.Repo.Migrations.CreateReportsAndSanctions do
  use Ecto.Migration

  def change do
    create table(:reports) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :reporter_id, references(:users, on_delete: :delete_all), null: false
      add :target_type, :string, null: false
      add :target_id, :integer, null: false
      add :target_user_id, references(:users, on_delete: :nilify_all)
      add :target_label, :string, null: false
      add :content_snapshot, :text, null: false
      add :category, :string, null: false
      add :reason, :text
      add :status, :string, null: false, default: "open"
      add :resolution_notes, :text
      add :content_deleted, :boolean, null: false, default: false
      add :handled_by_id, references(:users, on_delete: :nilify_all)
      add :handled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:reports, [:story_id, :status])

    create unique_index(:reports, [:reporter_id, :target_type, :target_id],
             where: "status = 'open'",
             name: :reports_one_open_per_target_index
           )

    create table(:sanctions) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :reason, :text, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime
      add :issued_by_id, references(:users, on_delete: :nilify_all)
      add :revoked_at, :utc_datetime
      add :revoked_by_id, references(:users, on_delete: :nilify_all)
      add :report_id, references(:reports, on_delete: :nilify_all)
      add :seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:sanctions, [:story_id, :user_id])
  end
end
