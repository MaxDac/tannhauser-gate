defmodule TannhauserGate.Repo.Migrations.CreateGuilds do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :max_guilds_per_character, :integer, null: false, default: 1
    end

    create table(:guilds) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :emblem_path, :string
      add :secret, :boolean, null: false, default: false
      add :open_join, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:guilds, [:story_id])
    create unique_index(:guilds, [:story_id, :name])

    create table(:guild_ranks) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0
      add :salary, :integer, null: false, default: 0
      add :leader, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:guild_ranks, [:guild_id])
    create unique_index(:guild_ranks, [:guild_id, :name])
    create constraint(:guild_ranks, :guild_ranks_salary_non_negative, check: "salary >= 0")

    create table(:guild_memberships) do
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :rank_id, references(:guild_ranks, on_delete: :nilify_all)
      add :status, :string, null: false
      add :last_paid_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:guild_memberships, [:guild_id, :character_id])
    create index(:guild_memberships, [:character_id])
    create index(:guild_memberships, [:rank_id])

    create constraint(:guild_memberships, :guild_memberships_status,
             check: "status IN ('requested', 'invited', 'active')"
           )

    create table(:guild_logs) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :rank_name, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:guild_logs, [:guild_id, :inserted_at])
    create index(:guild_logs, [:story_id])

    alter table(:forum_sections) do
      add :guild_id, references(:guilds, on_delete: :nilify_all)
    end

    create index(:forum_sections, [:guild_id])

    alter table(:locations) do
      add :guild_id, references(:guilds, on_delete: :nilify_all)
    end

    create index(:locations, [:guild_id])
  end
end
