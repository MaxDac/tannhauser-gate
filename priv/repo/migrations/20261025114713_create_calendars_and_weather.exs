defmodule TannhauserGate.Repo.Migrations.CreateCalendarsAndWeather do
  use Ecto.Migration

  def change do
    create table(:calendars) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :epoch_real, :utc_datetime, null: false
      add :epoch_year, :integer, null: false, default: 1
      add :epoch_month, :integer, null: false, default: 1
      add :epoch_day, :integer, null: false, default: 1
      add :epoch_hour, :integer, null: false, default: 0
      add :epoch_minute, :integer, null: false, default: 0
      add :ratio, :integer, null: false, default: 1
      add :month_names, {:array, :string}, null: false, default: []
      add :days_per_month, {:array, :integer}, null: false, default: []
      add :seasons, {:array, :string}, null: false, default: []
      add :weekday_names, {:array, :string}, null: false, default: []
      add :year_suffix, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:calendars, [:story_id])

    alter table(:stories) do
      add :weather_interval_hours, :integer, null: false, default: 6
    end

    create table(:weather_conditions) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :icon, :string, null: false
      add :description, :string
      add :weights, :map, null: false, default: %{}
      add :temp_min, :map, null: false, default: %{}
      add :temp_max, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:weather_conditions, [:story_id, :name])

    create table(:zone_weathers) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :zone_id, references(:zones, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :condition, :string, null: false
      add :icon, :string, null: false
      add :temperature, :integer
      add :description, :string
      add :set_by, :string, null: false
      add :set_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:zone_weathers, [:zone_id])
    create index(:zone_weathers, [:story_id])

    for table <- [:zone_events, :quests, :esiti] do
      alter table(table) do
        add :game_date_label, :string
      end
    end
  end
end
