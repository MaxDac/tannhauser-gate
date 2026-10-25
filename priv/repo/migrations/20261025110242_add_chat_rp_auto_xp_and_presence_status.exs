defmodule TannhauserGate.Repo.Migrations.AddChatRpAutoXpAndPresenceStatus do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :chat_min_length, :integer
      add :chat_max_length, :integer
      add :auto_xp_amount, :integer
      add :auto_xp_min_length, :integer
      add :auto_xp_daily_cap, :integer
      add :auto_xp_cooldown_minutes, :integer
    end

    alter table(:messages) do
      add :tag, :string, size: 60
      add :recipient_character_id, references(:characters, on_delete: :nilify_all)
    end

    create index(:messages, [:recipient_character_id])

    alter table(:archived_messages) do
      add :tag, :string, size: 60
      add :recipient_character_id, references(:characters, on_delete: :nilify_all)
      add :recipient_name, :string
    end

    alter table(:xp_entries) do
      add :source, :string, null: false, default: "manual"
    end

    create index(:xp_entries, [:character_id, :source, :inserted_at])

    create table(:presence_statuses) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "available"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:presence_statuses, [:user_id, :story_id])
  end
end
