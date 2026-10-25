defmodule TannhauserGate.Repo.Migrations.AddControlStyleToStories do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      add :control_style, :map, null: false, default: %{}
    end
  end
end
