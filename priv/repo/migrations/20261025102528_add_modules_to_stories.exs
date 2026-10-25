defmodule TannhauserGate.Repo.Migrations.AddModulesToStories do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :modules, :map, null: false, default: %{}
    end
  end
end
