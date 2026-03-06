defmodule Omiai.Repo.Migrations.CreateUsersAndFriendships do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :quicdial_id, :string, null: false
      add :display_name, :string, null: false
      add :avatar_id, :string, default: "kyu-kun"
      add :password_hash, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:quicdial_id])

    create table(:friendships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :requester_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recipient_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "pending"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:friendships, [:requester_id, :recipient_id])
    create index(:friendships, [:recipient_id])
    create index(:friendships, [:status])
  end
end
