defmodule TannhauserGate.Repo.Migrations.AddReturnToChatCommunityAndTerms do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :accepted_terms_at, :utc_datetime
    end

    alter table(:stories) do
      add :community_url, :string, size: 500
      add :community_label, :string
    end

    create table(:user_story_locations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :location_id, references(:locations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_story_locations, [:user_id, :story_id])
    create index(:user_story_locations, [:location_id])
  end
end
