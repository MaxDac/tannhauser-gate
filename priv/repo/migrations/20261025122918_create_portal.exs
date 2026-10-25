defmodule TannhauserGate.Repo.Migrations.CreatePortal do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :genres, {:array, :string}, null: false, default: []
      add :lifecycle, :string, null: false, default: "open"
      add :content_rating, :string, null: false, default: "16"
      add :pitch, :string
      add :banner_path, :string
    end

    create table(:gdr_reviews) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :graphics, :integer, null: false
      add :setting, :integer, null: false
      add :play_level, :integer, null: false
      add :technical, :integer, null: false
      add :features, :integer, null: false
      add :documentation, :integer, null: false
      add :management, :integer, null: false
      add :advice, :text
      add :conclusion, :text, null: false
      add :gm_reply, :text
      add :replied_at, :utc_datetime
      add :hidden_at, :utc_datetime
      add :hidden_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gdr_reviews, [:story_id, :user_id])
    create index(:gdr_reviews, [:user_id])

    create table(:gdr_votes) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :month, :date, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:gdr_votes, [:story_id, :user_id, :month])
    create index(:gdr_votes, [:month])
    create index(:gdr_votes, [:user_id])
  end
end
