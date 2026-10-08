defmodule TannhauserGate.Repo.Migrations.CreateGameTables do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
    end

    create table(:stories) do
      add :name, :string, null: false
      add :summary, :text
      add :world_background, :text
      add :customs, :text
      add :map_svg, :text
      add :map_width, :integer, null: false, default: 1000
      add :map_height, :integer, null: false, default: 700
      add :is_default, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:stories, [:name])

    create table(:locations) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :area, :text, null: false
      add :color, :string, null: false, default: "#ff7a1a"

      timestamps(type: :utc_datetime)
    end

    create index(:locations, [:story_id])
    create unique_index(:locations, [:story_id, :name])

    create table(:characters) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :background, :text
      add :avatar_path, :string

      timestamps(type: :utc_datetime)
    end

    create index(:characters, [:user_id])
    create index(:characters, [:story_id])

    create table(:messages) do
      add :location_id, references(:locations, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:location_id, :inserted_at])

    create table(:forum_sections) do
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:forum_sections, [:name])

    create table(:forum_topics) do
      add :section_id, references(:forum_sections, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:forum_topics, [:section_id])

    create table(:forum_posts) do
      add :topic_id, references(:forum_topics, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:forum_posts, [:topic_id, :inserted_at])
  end
end
