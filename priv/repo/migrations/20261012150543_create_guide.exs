defmodule TannhauserGate.Repo.Migrations.CreateGuide do
  use Ecto.Migration

  # The legacy `stories.world_background`, `rules` and `customs` text fields are
  # copied into default guide pages. The columns are kept (unmapped and
  # deprecated) so rolling back loses nothing; a later release drops them.
  def up do
    create table(:guide_sections) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:guide_sections, [:story_id, :position])

    create table(:guide_pages) do
      add :section_id, references(:guide_sections, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text, null: false, default: ""
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:guide_pages, [:section_id, :position])

    flush()

    execute """
    INSERT INTO guide_sections (story_id, title, position, inserted_at, updated_at)
    SELECT id, 'The world', 0, now(), now()
    FROM stories
    WHERE coalesce(btrim(world_background), '') <> ''
       OR coalesce(btrim(rules), '') <> ''
       OR coalesce(btrim(customs), '') <> ''
    """

    for {column, title, position} <- [
          {"world_background", "Background", 0},
          {"rules", "Rules", 1},
          {"customs", "Customs", 2}
        ] do
      execute """
      INSERT INTO guide_pages (section_id, title, body, position, inserted_at, updated_at)
      SELECT gs.id, '#{title}', s.#{column}, #{position}, now(), now()
      FROM stories s
      JOIN guide_sections gs ON gs.story_id = s.id AND gs.title = 'The world'
      WHERE coalesce(btrim(s.#{column}), '') <> ''
      """
    end
  end

  def down do
    drop table(:guide_pages)
    drop table(:guide_sections)
  end
end
