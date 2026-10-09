defmodule TannhauserGate.Repo.Migrations.ReplaceRoleWithFlags do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :admin, :boolean, null: false, default: false
      add :gm, :boolean, null: false, default: false
    end

    execute "UPDATE users SET admin = true WHERE role = 'admin'"

    alter table(:users) do
      remove :role
    end
  end

  def down do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
    end

    execute "UPDATE users SET role = 'admin' WHERE admin"

    alter table(:users) do
      remove :admin
      remove :gm
    end
  end
end
