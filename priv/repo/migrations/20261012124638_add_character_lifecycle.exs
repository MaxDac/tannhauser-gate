defmodule TannhauserGate.Repo.Migrations.AddCharacterLifecycle do
  use Ecto.Migration

  def up do
    create table(:character_states) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :can_play, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:character_states, [:story_id, :name])

    alter table(:characters) do
      add :approval_status, :string, null: false, default: "draft"
      add :review_notes, :text
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime
      add :state_id, references(:character_states, on_delete: :nilify_all)
      add :is_npc, :boolean, null: false, default: false
      add :player_notes, :text
      add :off_game_info, :text
      add :master_notes, :text
    end

    create index(:characters, [:story_id, :approval_status])
    create index(:characters, [:state_id])

    # Characters created before the approval flow keep playing.
    execute "UPDATE characters SET approval_status = 'approved'"

    execute """
    INSERT INTO character_states (story_id, name, can_play, position, inserted_at, updated_at)
    SELECT id, 'Active', true, 0, now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc' FROM stories
    """

    execute """
    UPDATE characters AS c SET state_id = s.id
    FROM character_states AS s
    WHERE s.story_id = c.story_id AND s.name = 'Active'
    """

    # NPCs are owned by the GDR: only player characters are one per user.
    drop unique_index(:characters, [:user_id, :story_id])

    create unique_index(:characters, [:user_id, :story_id],
             name: :characters_user_id_story_id_index,
             where: "is_npc = false"
           )
  end

  def down do
    drop unique_index(:characters, [:user_id, :story_id],
           name: :characters_user_id_story_id_index
         )

    execute "DELETE FROM characters WHERE is_npc"
    create unique_index(:characters, [:user_id, :story_id])

    drop index(:characters, [:state_id])
    drop index(:characters, [:story_id, :approval_status])

    alter table(:characters) do
      remove :approval_status
      remove :review_notes
      remove :reviewed_by_id
      remove :reviewed_at
      remove :state_id
      remove :is_npc
      remove :player_notes
      remove :off_game_info
      remove :master_notes
    end

    drop table(:character_states)
  end
end
