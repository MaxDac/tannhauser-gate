defmodule TannhauserGate.Repo.Migrations.CreateDiariesAndBoards do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :sheet_template, :text
    end

    create table(:diary_entries) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :body, :text, null: false
      add :game_date_label, :string
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :utc_datetime)
    end

    create index(:diary_entries, [:character_id, :inserted_at])
    create index(:diary_entries, [:story_id])

    create constraint(:diary_entries, :diary_entries_visibility_check,
             check: "visibility IN ('public', 'masters', 'private')"
           )

    create table(:character_images) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :path, :string, null: false
      add :caption, :string

      timestamps(type: :utc_datetime)
    end

    create index(:character_images, [:character_id])

    create table(:announcements) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :body, :text, null: false
      add :pinned, :boolean, null: false, default: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create index(:announcements, [:story_id, :inserted_at])

    create table(:announcement_reads) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :last_seen_at, :utc_datetime_usec, null: false
    end

    create unique_index(:announcement_reads, [:user_id, :story_id])

    create table(:boards) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :location_id, references(:locations, on_delete: :delete_all)
      add :zone_id, references(:zones, on_delete: :delete_all)
      # Deleting the guild deletes its boards, so restricted notices never leak.
      add :guild_id, references(:guilds, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:boards, [:story_id])
    create index(:boards, [:location_id])
    create index(:boards, [:zone_id])
    create index(:boards, [:guild_id])

    create constraint(:boards, :boards_place_check,
             check: "(location_id IS NULL) <> (zone_id IS NULL)"
           )

    create table(:board_notices) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :title, :string
      add :body, :text, null: false
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:board_notices, [:board_id, :inserted_at])
    create index(:board_notices, [:character_id])
  end
end
