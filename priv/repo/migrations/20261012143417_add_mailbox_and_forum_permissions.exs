defmodule TannhauserGate.Repo.Migrations.AddMailboxAndForumPermissions do
  use Ecto.Migration

  def change do
    # Per-GDR character-to-character mailbox. A nil recipient (and a sender
    # flagged `from_masters`) stands for "The masters", a mailbox shared by
    # every master of the GDR.
    create table(:mail_messages) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :sender_user_id, references(:users, on_delete: :nilify_all)
      add :sender_character_id, references(:characters, on_delete: :nilify_all)
      add :sender_name, :string, null: false
      add :from_masters, :boolean, null: false, default: false
      add :recipient_character_id, references(:characters, on_delete: :delete_all)
      add :reply_to_id, references(:mail_messages, on_delete: :nilify_all)
      add :subject, :string, null: false
      add :body, :text, null: false
      add :read_at, :utc_datetime
      add :sender_deleted_at, :utc_datetime
      add :recipient_deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:mail_messages, [:story_id])
    create index(:mail_messages, [:recipient_character_id, :read_at])
    create index(:mail_messages, [:sender_character_id])
    create index(:mail_messages, [:sender_user_id])

    alter table(:forum_sections) do
      add :on_game, :boolean, null: false, default: false
      add :visibility, :string, null: false, default: "all"
    end

    alter table(:forum_topics) do
      add :character_id, references(:characters, on_delete: :nilify_all)
      add :locked, :boolean, null: false, default: false
      add :pinned, :boolean, null: false, default: false
    end

    alter table(:forum_posts) do
      add :character_id, references(:characters, on_delete: :nilify_all)
      add :edited_at, :utc_datetime
    end

    create table(:forum_reads) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :topic_id, references(:forum_topics, on_delete: :delete_all), null: false
      add :last_read_post_id, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime, inserted_at: false)
    end

    create unique_index(:forum_reads, [:user_id, :topic_id])
  end
end
