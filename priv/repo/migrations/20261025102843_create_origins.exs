defmodule TannhauserGate.Repo.Migrations.CreateOrigins do
  use Ecto.Migration

  def change do
    create table(:origin_groups) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, null: false, default: 0
      add :required, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:origin_groups, [:story_id])
    create unique_index(:origin_groups, [:story_id, :name])

    create table(:origin_options) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :group_id, references(:origin_groups, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :image_path, :string
      add :requires_approval, :boolean, null: false, default: false
      add :bonuses, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:origin_options, [:story_id])
    create unique_index(:origin_options, [:group_id, :name])

    create table(:character_origins) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :origin_group_id, references(:origin_groups, on_delete: :delete_all), null: false
      add :origin_option_id, references(:origin_options, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:character_origins, [:character_id, :origin_group_id])
    create index(:character_origins, [:origin_option_id])
    create index(:character_origins, [:origin_group_id])
  end
end
