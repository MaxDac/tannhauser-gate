defmodule TannhauserGate.Repo.Migrations.CreateGdrFeatures do
  use Ecto.Migration

  # A "story" is a GDR (role playing game) run by a game master.
  def up do
    abort_on_duplicate_characters!()

    alter table(:stories) do
      add :owner_id, references(:users, on_delete: :nilify_all)
      add :rules, :text
      add :status, :string, null: false, default: "draft"
      add :theme, :string, null: false, default: "tannhauser"
      add :theme_overrides, :map, null: false, default: %{}
      add :currency_name, :string, null: false, default: "credits"
      add :pay_interval_hours, :integer, null: false, default: 24
    end

    execute "UPDATE stories SET status = 'published'"
    create unique_index(:stories, [:owner_id])

    create table(:gdr_requests) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :pitch, :text
      add :status, :string, null: false, default: "pending"
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      add :story_id, references(:stories, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:gdr_requests, [:user_id])
    create index(:gdr_requests, [:status])

    create unique_index(:gdr_requests, [:user_id],
             where: "status = 'pending'",
             name: :gdr_requests_one_pending_per_user
           )

    create table(:sheet_items) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :min_value, :integer, null: false, default: 0
      add :max_value, :integer, null: false, default: 10
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:sheet_items, [:story_id, :kind])
    create unique_index(:sheet_items, [:story_id, :kind, :name])

    create table(:jobs) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :pay, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:jobs, [:story_id, :name])

    alter table(:characters) do
      add :balance, :bigint, null: false, default: 0
      add :job_id, references(:jobs, on_delete: :nilify_all)
      add :last_paid_at, :utc_datetime
    end

    create unique_index(:characters, [:user_id, :story_id])
    create index(:characters, [:job_id])

    create table(:character_traits) do
      add :character_id, references(:characters, on_delete: :delete_all), null: false
      add :sheet_item_id, references(:sheet_items, on_delete: :delete_all), null: false
      add :value, :integer, null: false, default: 0
    end

    create unique_index(:character_traits, [:character_id, :sheet_item_id])

    create table(:bank_transactions) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :from_character_id, references(:characters, on_delete: :nilify_all)
      add :to_character_id, references(:characters, on_delete: :nilify_all)
      add :amount, :bigint, null: false
      add :kind, :string, null: false
      add :note, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:bank_transactions, [:story_id])
    create index(:bank_transactions, [:from_character_id])
    create index(:bank_transactions, [:to_character_id])

    alter table(:forum_sections) do
      add :story_id, references(:stories, on_delete: :delete_all)
    end

    # Forum sections used to be global: they move to the default GDR. If no
    # GDR exists yet, create the Tannhauser Gate one (seeds reuse it by name)
    # rather than losing the forum content.
    execute """
            INSERT INTO stories (name, status, is_default, inserted_at, updated_at)
            SELECT 'Tannhauser Gate', 'published', true, now(), now()
            WHERE NOT EXISTS (SELECT 1 FROM stories)
              AND EXISTS (SELECT 1 FROM forum_sections)
            """,
            ""

    execute """
            UPDATE forum_sections SET story_id =
              (SELECT id FROM stories ORDER BY is_default DESC, id LIMIT 1)
            """,
            ""

    execute "ALTER TABLE forum_sections ALTER COLUMN story_id SET NOT NULL", ""

    drop unique_index(:forum_sections, [:name])
    create unique_index(:forum_sections, [:story_id, :name])
  end

  def down do
    drop unique_index(:forum_sections, [:story_id, :name])

    # Section names were globally unique before: disambiguate collisions
    # between GDRs so the old index can be restored. Loop because a generated
    # name could itself already exist.
    execute """
    DO $$
    BEGIN
      LOOP
        UPDATE forum_sections s SET name = s.name || ' (#' || s.id || ')'
        WHERE EXISTS (
          SELECT 1 FROM forum_sections o WHERE o.name = s.name AND o.id < s.id
        );
        EXIT WHEN NOT FOUND;
      END LOOP;
    END $$;
    """

    create unique_index(:forum_sections, [:name])

    alter table(:forum_sections) do
      remove :story_id
    end

    drop table(:bank_transactions)
    drop table(:character_traits)

    drop_if_exists unique_index(:characters, [:user_id, :story_id])

    alter table(:characters) do
      remove :balance
      remove :job_id
      remove :last_paid_at
    end

    drop table(:jobs)
    drop table(:sheet_items)
    drop table(:gdr_requests)

    alter table(:stories) do
      remove :owner_id
      remove :rules
      remove :status
      remove :theme
      remove :theme_overrides
      remove :currency_name
      remove :pay_interval_hours
    end
  end

  # Players may now have a single character per GDR. Older data allowed more,
  # and picking which character to drop is a human decision: stop with a list
  # of the offenders instead of deleting anyone's character.
  defp abort_on_duplicate_characters! do
    %{rows: rows} =
      repo().query!("""
      SELECT user_id, story_id, array_agg(id ORDER BY id)
      FROM characters
      GROUP BY user_id, story_id
      HAVING count(*) > 1
      """)

    if rows != [] do
      details =
        Enum.map_join(rows, "\n", fn [user_id, story_id, ids] ->
          "  user #{user_id}, story #{story_id}: characters #{inspect(ids)}"
        end)

      raise """
      Some users have more than one character in the same story, but a user can
      now have only one character per GDR. Delete the extra characters, then
      run the migration again:

      #{details}
      """
    end
  end
end
