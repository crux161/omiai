defmodule Omiai.Repo.Migrations.AddPasswordResetFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :password_reset_token, :string
      add :password_reset_expires_at, :utc_datetime
    end

    create index(:users, [:password_reset_token])
  end
end
