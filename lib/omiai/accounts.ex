defmodule Omiai.Accounts do
  @moduledoc """
  Context for user accounts, authentication, and friendships.
  """

  import Ecto.Query

  alias Omiai.Repo
  alias Omiai.Accounts.{User, Friendship}

  @token_salt "omiai_session"
  @token_max_age_seconds 30 * 24 * 3600

  # ---------------------------------------------------------------------------
  # Quicdial Code Generation
  # ---------------------------------------------------------------------------

  @doc """
  Generate a unique Quicdial ID in ###-###-### format.
  Retries up to `max_attempts` times to avoid collisions.
  """
  def generate_quicdial_id(max_attempts \\ 20) do
    generate_quicdial_id_loop(max_attempts)
  end

  defp generate_quicdial_id_loop(0), do: {:error, :exhausted_attempts}

  defp generate_quicdial_id_loop(remaining) do
    code = random_quicdial_code()

    if is_nil(get_user_by_quicdial_id(code)) do
      {:ok, code}
    else
      generate_quicdial_id_loop(remaining - 1)
    end
  end

  defp random_quicdial_code do
    a = :rand.uniform(1_000) - 1
    b = :rand.uniform(1_000) - 1
    c = :rand.uniform(1_000) - 1

    :io_lib.format("~3..0B-~3..0B-~3..0B", [a, b, c])
    |> IO.iodata_to_binary()
  end

  # ---------------------------------------------------------------------------
  # Registration & Authentication
  # ---------------------------------------------------------------------------

  @doc """
  Register a new user. If `quicdial_id` is nil or empty, one is auto-generated.
  """
  def register_user(attrs) when is_map(attrs) do
    attrs = maybe_assign_quicdial_id(attrs)

    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  defp maybe_assign_quicdial_id(%{quicdial_id: qid} = attrs)
       when is_binary(qid) and byte_size(qid) > 0 do
    attrs
  end

  defp maybe_assign_quicdial_id(attrs) do
    case generate_quicdial_id() do
      {:ok, code} -> Map.put(attrs, :quicdial_id, code)
      {:error, _} -> attrs
    end
  end

  @doc "Authenticate by quicdial_id and password."
  def authenticate(quicdial_id, password) when is_binary(quicdial_id) and is_binary(password) do
    user = get_user_by_quicdial_id(quicdial_id)

    cond do
      is_nil(user) ->
        Argon2.no_user_verify()
        {:error, :invalid_credentials}

      Argon2.verify_pass(password, user.password_hash) ->
        {:ok, user}

      true ->
        {:error, :invalid_credentials}
    end
  end

  # ---------------------------------------------------------------------------
  # Session Tokens (Phoenix.Token)
  # ---------------------------------------------------------------------------

  @doc "Generate a session token for a user."
  def generate_session_token(%User{} = user) do
    Phoenix.Token.sign(OmiaiWeb.Endpoint, @token_salt, %{
      user_id: user.id,
      quicdial_id: user.quicdial_id
    })
  end

  @doc "Verify a session token. Returns `{:ok, payload}` or `{:error, reason}`."
  def verify_session_token(token) when is_binary(token) do
    Phoenix.Token.verify(OmiaiWeb.Endpoint, @token_salt, token,
      max_age: @token_max_age_seconds
    )
  end

  # ---------------------------------------------------------------------------
  # User Lookups
  # ---------------------------------------------------------------------------

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_quicdial_id(quicdial_id) when is_binary(quicdial_id) do
    Repo.get_by(User, quicdial_id: String.trim(quicdial_id))
  end

  def update_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Admin Functions
  # ---------------------------------------------------------------------------

  def list_users do
    from(u in User, order_by: [desc: u.inserted_at])
    |> Repo.all()
  end

  def admin_update_user(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  def admin_reset_password(%User{} = user, attrs) do
    user
    |> User.reset_password_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def record_login(%User{} = user) do
    user
    |> User.last_login_changeset(%{last_login_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Password Reset
  # ---------------------------------------------------------------------------

  @reset_token_ttl_minutes 30

  @doc """
  Request a password reset for a user identified by quicdial_id.
  Returns `{:ok, token}` or `{:error, :not_found}`.
  In production this would send an email; for now it returns the token directly.
  """
  def request_password_reset(quicdial_id) when is_binary(quicdial_id) do
    case get_user_by_quicdial_id(quicdial_id) do
      nil ->
        {:error, :not_found}

      user ->
        token = generate_reset_token()
        expires_at =
          DateTime.utc_now()
          |> DateTime.add(@reset_token_ttl_minutes * 60, :second)
          |> DateTime.truncate(:second)

        user
        |> User.password_reset_changeset(%{
          password_reset_token: token,
          password_reset_expires_at: expires_at
        })
        |> Repo.update()
        |> case do
          {:ok, _user} -> {:ok, token}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Reset a user's password using a valid reset token.
  Returns `{:ok, user}` or `{:error, reason}`.
  """
  def reset_password(token, new_password) when is_binary(token) and is_binary(new_password) do
    case Repo.get_by(User, password_reset_token: token) do
      nil ->
        {:error, :invalid_token}

      user ->
        now = DateTime.utc_now()

        if user.password_reset_expires_at && DateTime.compare(user.password_reset_expires_at, now) == :gt do
          user
          |> User.reset_password_changeset(%{password: new_password})
          |> Repo.update()
        else
          {:error, :token_expired}
        end
    end
  end

  defp generate_reset_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  # ---------------------------------------------------------------------------
  # Friendships
  # ---------------------------------------------------------------------------

  @doc "Send a friend request from `requester_id` to the user with `recipient_quicdial_id`."
  def send_friend_request(requester_id, recipient_quicdial_id)
      when is_binary(requester_id) and is_binary(recipient_quicdial_id) do
    case get_user_by_quicdial_id(recipient_quicdial_id) do
      nil ->
        {:error, :recipient_not_found}

      recipient ->
        if requester_id == recipient.id do
          {:error, :cannot_friend_self}
        else
          existing = get_friendship_between(requester_id, recipient.id)
          handle_friend_request(existing, requester_id, recipient)
        end
    end
  end

  defp handle_friend_request(nil, requester_id, recipient) do
    %Friendship{}
    |> Friendship.changeset(%{
      requester_id: requester_id,
      recipient_id: recipient.id,
      status: "pending"
    })
    |> Repo.insert()
  end

  defp handle_friend_request(%Friendship{status: "declined"} = f, _requester_id, _recipient) do
    f
    |> Friendship.changeset(%{status: "pending"})
    |> Repo.update()
  end

  defp handle_friend_request(%Friendship{status: "pending"}, _requester_id, _recipient) do
    {:error, :already_pending}
  end

  defp handle_friend_request(%Friendship{status: "accepted"}, _requester_id, _recipient) do
    {:error, :already_friends}
  end

  @doc "Accept a pending friend request."
  def accept_friend_request(friendship_id, recipient_id) do
    case Repo.get(Friendship, friendship_id) do
      nil ->
        {:error, :not_found}

      %Friendship{recipient_id: ^recipient_id, status: "pending"} = f ->
        f |> Friendship.changeset(%{status: "accepted"}) |> Repo.update()

      %Friendship{} ->
        {:error, :unauthorized}
    end
  end

  @doc "Decline a pending friend request."
  def decline_friend_request(friendship_id, recipient_id) do
    case Repo.get(Friendship, friendship_id) do
      nil ->
        {:error, :not_found}

      %Friendship{recipient_id: ^recipient_id, status: "pending"} = f ->
        f |> Friendship.changeset(%{status: "declined"}) |> Repo.update()

      %Friendship{} ->
        {:error, :unauthorized}
    end
  end

  @doc "Remove a friendship (unfriend). Either side can unfriend."
  def remove_friendship(user_id, friend_quicdial_id) when is_binary(user_id) do
    case get_user_by_quicdial_id(friend_quicdial_id) do
      nil ->
        {:error, :not_found}

      friend ->
        query =
          from f in Friendship,
            where:
              (f.requester_id == ^user_id and f.recipient_id == ^friend.id) or
                (f.requester_id == ^friend.id and f.recipient_id == ^user_id)

        case Repo.delete_all(query) do
          {0, _} -> {:error, :not_found}
          {_n, _} -> :ok
        end
    end
  end

  @doc "List accepted friends for a user, returning user details."
  def list_friends(user_id) when is_binary(user_id) do
    sent_query =
      from f in Friendship,
        join: u in User,
        on: u.id == f.recipient_id,
        where: f.requester_id == ^user_id and f.status == "accepted",
        select: %{
          friendship_id: f.id,
          quicdial_id: u.quicdial_id,
          display_name: u.display_name,
          avatar_id: u.avatar_id
        }

    received_query =
      from f in Friendship,
        join: u in User,
        on: u.id == f.requester_id,
        where: f.recipient_id == ^user_id and f.status == "accepted",
        select: %{
          friendship_id: f.id,
          quicdial_id: u.quicdial_id,
          display_name: u.display_name,
          avatar_id: u.avatar_id
        }

    Repo.all(sent_query) ++ Repo.all(received_query)
  end

  @doc "List pending incoming friend requests for a user."
  def list_pending_requests(user_id) when is_binary(user_id) do
    from(f in Friendship,
      join: u in User,
      on: u.id == f.requester_id,
      where: f.recipient_id == ^user_id and f.status == "pending",
      select: %{
        friendship_id: f.id,
        from_quicdial_id: u.quicdial_id,
        from_display_name: u.display_name,
        from_avatar_id: u.avatar_id,
        created_at: f.inserted_at
      }
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp get_friendship_between(user_a_id, user_b_id) do
    from(f in Friendship,
      where:
        (f.requester_id == ^user_a_id and f.recipient_id == ^user_b_id) or
          (f.requester_id == ^user_b_id and f.recipient_id == ^user_a_id)
    )
    |> Repo.one()
  end
end
