defmodule TannhauserGate.Repo.Migrations.AddMustChangePasswordToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :must_change_password, :boolean, null: false, default: false
    end
  end
end
