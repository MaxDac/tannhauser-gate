defmodule TannhauserGate.Repo.Migrations.CreateStoryMasters do
  use Ecto.Migration

  def change do
    create table(:story_masters) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:story_masters, [:story_id, :user_id])
    create index(:story_masters, [:user_id])
  end
end
