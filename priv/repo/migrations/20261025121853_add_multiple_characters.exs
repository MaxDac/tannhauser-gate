defmodule TannhauserGate.Repo.Migrations.AddMultipleCharacters do
  use Ecto.Migration

  def up do
    alter table(:stories) do
      add :max_characters_per_user, :integer, null: false, default: 1
      add :block_alt_transfers, :boolean, null: false, default: true
      add :block_alt_mail, :boolean, null: false, default: true
      add :block_alt_whispers, :boolean, null: false, default: true
    end

    # The limit is now a story setting, enforced in `Characters.create_character/3`.
    drop unique_index(:characters, [:user_id, :story_id],
           name: :characters_user_id_story_id_index
         )

    create index(:characters, [:user_id, :story_id],
             name: :characters_user_id_story_id_lookup_index
           )

    create table(:user_active_characters) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_active_characters, [:user_id, :story_id])
    create index(:user_active_characters, [:character_id])
  end

  def down do
    abort_on_duplicate_characters!()

    drop table(:user_active_characters)

    drop index(:characters, [:user_id, :story_id],
           name: :characters_user_id_story_id_lookup_index
         )

    create unique_index(:characters, [:user_id, :story_id],
             name: :characters_user_id_story_id_index,
             where: "is_npc = false"
           )

    alter table(:stories) do
      remove :max_characters_per_user
      remove :block_alt_transfers
      remove :block_alt_mail
      remove :block_alt_whispers
    end
  end

  # Going back to one character per user per GDR: picking which character to
  # drop is a human decision, so stop with the list of the offenders instead
  # of deleting anyone's character.
  defp abort_on_duplicate_characters! do
    %{rows: rows} =
      repo().query!("""
      SELECT user_id, story_id, array_agg(id ORDER BY id)
      FROM characters
      WHERE is_npc = false
      GROUP BY user_id, story_id
      HAVING count(*) > 1
      """)

    if rows != [] do
      details =
        Enum.map_join(rows, "\n", fn [user_id, story_id, ids] ->
          "  user #{user_id}, story #{story_id}: characters #{inspect(ids)}"
        end)

      raise """
      Some users have more than one character in the same story, but before this
      migration a user can have only one character per GDR. Delete the extra
      characters, then roll back again:

      #{details}
      """
    end
  end
end
