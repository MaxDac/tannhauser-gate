defmodule TannhauserGate.Repo.Migrations.AddSheetMechanics do
  use Ecto.Migration

  def up do
    # Stable keys for formulas (e.g. "composure + resolve").
    alter table(:sheet_items) do
      add :slug, :string
    end

    execute """
    UPDATE sheet_items
    SET slug = left(btrim(regexp_replace(lower(name), '[^a-z0-9]+', '_', 'g'), '_'), 40)
    """

    execute """
    UPDATE sheet_items
    SET slug = 'item_' || id
    WHERE slug = '' OR slug ~ '^[0-9]' OR slug IN ('current', 'next', 'min', 'max')
    """

    execute """
    UPDATE sheet_items AS i SET slug = left(i.slug, 30) || '_' || i.id
    FROM (
      SELECT id, row_number() OVER (PARTITION BY story_id, slug ORDER BY id) AS n
      FROM sheet_items
    ) AS d
    WHERE d.id = i.id AND d.n > 1
    """

    execute "ALTER TABLE sheet_items ALTER COLUMN slug SET NOT NULL"
    create unique_index(:sheet_items, [:story_id, :slug])

    # Creation budgets and XP costs per sheet category (attribute/skill/power).
    create table(:sheet_categories) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :creation_mode, :string, null: false, default: "free"
      add :creation_points, :integer
      add :creation_distribution, :string
      add :starting_value, :integer, null: false, default: 0
      add :xp_cost_formula, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sheet_categories, [:story_id, :kind])

    create table(:trackers) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :max_formula, :string, null: false
      add :damage_types, {:array, :string}, null: false, default: []
      add :starts_full, :boolean, null: false, default: true
      add :public, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:trackers, [:story_id, :slug])

    create table(:character_trackers) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :tracker_id, references(:trackers, on_delete: :delete_all), null: false
      add :value, :integer
      add :damage, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:character_trackers, [:character_id, :tracker_id])
    create index(:character_trackers, [:tracker_id])

    create table(:xp_entries) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :amount, :integer, null: false
      add :reason, :text
      add :sheet_item_id, references(:sheet_items, on_delete: :nilify_all)
      add :item_name, :string
      add :from_value, :integer
      add :to_value, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:xp_entries, [:character_id])
    create index(:xp_entries, [:story_id, :inserted_at])
    create index(:xp_entries, [:sheet_item_id])
    create index(:xp_entries, [:author_id])
  end

  def down do
    drop table(:xp_entries)
    drop table(:character_trackers)
    drop table(:trackers)
    drop table(:sheet_categories)
    drop unique_index(:sheet_items, [:story_id, :slug])

    alter table(:sheet_items) do
      remove :slug
    end
  end
end
