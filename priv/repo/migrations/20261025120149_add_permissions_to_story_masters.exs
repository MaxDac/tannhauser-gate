defmodule TannhauserGate.Repo.Migrations.AddPermissionsToStoryMasters do
  use Ecto.Migration

  # Every flag defaults to true, so the existing masters keep all their powers.
  def change do
    alter table(:story_masters) do
      add :can_moderate, :boolean, null: false, default: true
      add :can_approve_characters, :boolean, null: false, default: true
      add :can_award_xp, :boolean, null: false, default: true
      add :can_manage_esiti_quests, :boolean, null: false, default: true
      add :can_manage_economy, :boolean, null: false, default: true
      add :can_manage_world, :boolean, null: false, default: true
    end
  end
end
