defmodule Omiai.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :quicdial_id, :string
    field :display_name, :string
    field :avatar_id, :string, default: "kyu-kun"
    field :password_hash, :string
    field :password, :string, virtual: true, redact: true
    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for new user registration."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:quicdial_id, :display_name, :password, :avatar_id])
    |> validate_required([:quicdial_id, :display_name, :password])
    |> validate_length(:quicdial_id, min: 3, max: 64)
    |> validate_format(:quicdial_id, ~r/^[A-Za-z0-9_:\-\.\/=+]+$/, message: "invalid characters")
    |> validate_length(:display_name, min: 1, max: 100)
    |> validate_length(:password, min: 6, max: 128)
    |> unique_constraint(:quicdial_id)
    |> hash_password()
  end

  @doc "Changeset for updating display name or avatar."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :avatar_id])
    |> validate_length(:display_name, min: 1, max: 100)
  end

  defp hash_password(%{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset
end
