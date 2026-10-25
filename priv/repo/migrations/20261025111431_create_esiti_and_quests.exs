defmodule TannhauserGate.Repo.Migrations.CreateEsitiAndQuests do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :esiti_max_open, :integer, default: 2
      add :esiti_min_xp, :integer
    end

    create table(:esiti) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :body, :text, null: false
      add :location_id, references(:locations, on_delete: :nilify_all)
      add :zone_id, references(:zones, on_delete: :nilify_all)
      add :status, :string, null: false, default: "open"
      add :claimed_by_id, references(:users, on_delete: :nilify_all)
      add :claimed_at, :utc_datetime
      add :resolved_by_id, references(:users, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime
      add :closed_at, :utc_datetime
      add :outcome, :text
      add :dice_result, :map
      add :effects, :map

      timestamps(type: :utc_datetime)
    end

    create index(:esiti, [:story_id, :status])
    create index(:esiti, [:character_id, :status])

    create constraint(:esiti, :esiti_status_check,
             check: "status IN ('open', 'claimed', 'resolved', 'closed')"
           )

    create table(:esito_characters, primary_key: false) do
      add :esito_id, references(:esiti, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
    end

    create unique_index(:esito_characters, [:esito_id, :character_id])
    create index(:esito_characters, [:character_id])

    create table(:esito_messages) do
      add :esito_id, references(:esiti, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :character_id, references(:characters, on_delete: :nilify_all)
      add :from_masters, :boolean, null: false, default: false
      add :author_name, :string, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:esito_messages, [:esito_id])

    create table(:quests) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :summary, :text
      add :held_on, :date, null: false
      add :location_id, references(:locations, on_delete: :nilify_all)
      add :master_id, references(:users, on_delete: :nilify_all)
      add :visibility, :string, null: false, default: "public"
      add :log_from, :utc_datetime
      add :log_to, :utc_datetime
      add :rewards_applied_at, :utc_datetime
      add :rewards_applied_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:quests, [:story_id, :held_on])

    create constraint(:quests, :quests_visibility_check,
             check: "visibility IN ('public', 'masters')"
           )

    create table(:quest_participants) do
      add :quest_id, references(:quests, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :xp, :integer, null: false, default: 0
      add :money, :integer, null: false, default: 0
      add :item_id, references(:items, on_delete: :nilify_all)
      add :item_quantity, :integer, null: false, default: 0
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quest_participants, [:quest_id, :character_id])
    create index(:quest_participants, [:character_id])
    create index(:quest_participants, [:item_id])
  end
end
