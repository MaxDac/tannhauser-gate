defmodule TannhauserGate.Repo.Migrations.AddChatFeatures do
  use Ecto.Migration

  def change do
    # Chat entry types: speech, ooc, narration (no character), status, dice.
    alter table(:messages) do
      add :kind, :string, null: false, default: "speech"
      add :data, :map
      modify :character_id, :bigint, null: true, from: {:bigint, null: false}
    end

    create table(:archived_messages) do
      add :location_id, references(:locations, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false, default: "speech"
      add :body, :text, null: false
      add :data, :map
      add :speaker_name, :string
      add :inserted_at, :utc_datetime, null: false
      add :archived_at, :utc_datetime, null: false
    end

    create index(:archived_messages, [:location_id, :inserted_at])

    alter table(:locations) do
      add :private, :boolean, null: false, default: false
      add :status, :text
      add :status_updated_at, :utc_datetime
    end

    alter table(:stories) do
      add :dice_config, :map
      add :archive_after_days, :integer, default: 30
    end

    create table(:location_bookings) do
      add :location_id, references(:locations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:location_bookings, [:location_id, :starts_at])
    create index(:location_bookings, [:user_id])

    create table(:booking_invites) do
      add :booking_id, references(:location_bookings, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
    end

    create unique_index(:booking_invites, [:booking_id, :character_id])
    create index(:booking_invites, [:character_id])
  end
end
