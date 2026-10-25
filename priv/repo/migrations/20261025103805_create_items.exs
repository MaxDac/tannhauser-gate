defmodule TannhauserGate.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :image_path, :string
      add :category, :string
      add :price, :integer, null: false, default: 0
      add :stackable, :boolean, null: false, default: true
      add :slot, :string
      add :modifiers, :map, null: false, default: %{}
      add :tracker_id, references(:trackers, on_delete: :nilify_all)
      add :effect_change, :integer
      add :effect_damage_type, :string
      add :consumed_on_use, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:items, [:story_id])
    create index(:items, [:tracker_id])
    create unique_index(:items, [:story_id, :name])
    create constraint(:items, :items_price_non_negative, check: "price >= 0")

    create table(:character_items) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false
      add :quantity, :integer, null: false, default: 1
      add :equipped, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:character_items, [:character_id, :item_id])
    create index(:character_items, [:item_id])

    create constraint(:character_items, :character_items_quantity_positive,
             check: "quantity >= 1"
           )

    create table(:shops) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :location_id, references(:locations, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create index(:shops, [:story_id])
    create index(:shops, [:location_id])
    create unique_index(:shops, [:story_id, :name])

    create table(:shop_listings) do
      add :shop_id, references(:shops, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false
      add :price, :integer
      add :stock, :integer
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shop_listings, [:shop_id, :item_id])
    create index(:shop_listings, [:item_id])

    create constraint(:shop_listings, :shop_listings_stock_non_negative,
             check: "stock IS NULL OR stock >= 0"
           )

    create constraint(:shop_listings, :shop_listings_price_non_negative,
             check: "price IS NULL OR price >= 0"
           )

    create table(:item_logs) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :target_character_id, references(:characters, on_delete: :nilify_all)
      add :item_id, references(:items, on_delete: :nilify_all)
      add :item_name, :string, null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :quantity, :integer, null: false
      add :action, :string, null: false
      add :note, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:item_logs, [:story_id, :inserted_at])
    create index(:item_logs, [:character_id])
    create index(:item_logs, [:target_character_id])
    create index(:item_logs, [:item_id])
    create index(:item_logs, [:user_id])
  end
end
