defmodule Omiai.Accounts.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  alias Omiai.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "friendships" do
    belongs_to :requester, User
    belongs_to :recipient, User
    field :status, :string, default: "pending"
    timestamps(type: :utc_datetime)
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:requester_id, :recipient_id, :status])
    |> validate_required([:requester_id, :recipient_id, :status])
    |> validate_inclusion(:status, ~w(pending accepted declined))
    |> unique_constraint([:requester_id, :recipient_id])
    |> foreign_key_constraint(:requester_id)
    |> foreign_key_constraint(:recipient_id)
  end
end
