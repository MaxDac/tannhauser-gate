defmodule TannhauserGate.Repo.Migrations.CreateZonesAndPeriodicActions do
  use Ecto.Migration

  def change do
    # Numeric properties every zone of a GDR carries (e.g. danger, resonance).
    create table(:zone_properties) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :default_value, :integer, null: false, default: 0
      add :public, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:zone_properties, [:story_id, :slug])

    create table(:zones) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      # property slug => integer value
      add :values, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:zones, [:story_id, :name])

    alter table(:locations) do
      add :zone_id, references(:zones, on_delete: :nilify_all)
    end

    create index(:locations, [:zone_id])

    create table(:zone_events) do
      add :zone_id, references(:zones, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :title, :string, null: false
      add :body, :text, null: false
      add :happened_on, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:zone_events, [:zone_id, :happened_on])

    create table(:periodic_actions) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :items, {:array, :string}, null: false, default: []
      add :difficulty_source, :string, null: false, default: "zone"
      add :zone_property, :string
      add :default_difficulty, :integer, null: false, default: 1
      add :success_tracker, :string
      add :success_damage_type, :string
      add :success_delta, :integer, null: false, default: 0
      add :failure_tracker, :string
      add :failure_damage_type, :string
      add :failure_delta, :integer, null: false, default: 0
      add :cooldown_hours, :integer, null: false, default: 24
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:periodic_actions, [:story_id, :name])

    create table(:periodic_action_difficulties) do
      add :action_id, references(:periodic_actions, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :difficulty, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:periodic_action_difficulties, [:action_id, :character_id])

    create table(:periodic_action_logs) do
      add :action_id, references(:periodic_actions, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :location_id, references(:locations, on_delete: :nilify_all)
      add :difficulty, :integer, null: false
      add :success, :boolean, null: false
      add :summary, :string, null: false
      add :effect, :string
      add :result, :map, null: false, default: %{}
      # Masters reset a cooldown by clearing this flag on the previous runs.
      add :counts_for_cooldown, :boolean, null: false, default: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:periodic_action_logs, [:action_id, :character_id, :inserted_at])
    create index(:periodic_action_logs, [:character_id])
  end
end
