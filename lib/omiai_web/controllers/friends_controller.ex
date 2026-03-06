defmodule OmiaiWeb.FriendsController do
  use OmiaiWeb, :controller

  alias Omiai.Accounts

  action_fallback OmiaiWeb.FallbackController

  def index(conn, _params) do
    user = conn.assigns.current_user
    friends = Accounts.list_friends(user.id)
    json(conn, %{friends: friends})
  end

  def pending_requests(conn, _params) do
    user = conn.assigns.current_user
    requests = Accounts.list_pending_requests(user.id)
    json(conn, %{requests: requests})
  end

  def create_request(conn, %{"quicdial_id" => quicdial_id}) do
    user = conn.assigns.current_user

    case Accounts.send_friend_request(user.id, quicdial_id) do
      {:ok, friendship} ->
        # Also broadcast in real-time if recipient is online
        OmiaiWeb.Endpoint.broadcast("user:" <> quicdial_id, "friend_request_received", %{
          "friendship_id" => friendship.id,
          "from_quicdial_id" => user.quicdial_id,
          "from_display_name" => user.display_name,
          "from_avatar_id" => user.avatar_id
        })

        OmiaiWeb.Endpoint.broadcast("peer:" <> quicdial_id, "friend_request_received", %{
          "friendship_id" => friendship.id,
          "from_quicdial_id" => user.quicdial_id,
          "from_display_name" => user.display_name,
          "from_avatar_id" => user.avatar_id
        })

        conn
        |> put_status(:created)
        |> json(%{friendship_id: friendship.id, status: friendship.status})

      {:error, :recipient_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "recipient_not_found"})

      {:error, :cannot_friend_self} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "cannot_friend_self"})

      {:error, :already_pending} ->
        conn |> put_status(:conflict) |> json(%{error: "already_pending"})

      {:error, :already_friends} ->
        conn |> put_status(:conflict) |> json(%{error: "already_friends"})

      {:error, %Ecto.Changeset{}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "request_failed"})
    end
  end

  def create_request(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing_quicdial_id"})
  end

  def accept(conn, %{"id" => friendship_id}) do
    user = conn.assigns.current_user

    case Accounts.accept_friend_request(friendship_id, user.id) do
      {:ok, friendship} ->
        # Notify the requester in real-time
        requester = Accounts.get_user!(friendship.requester_id)

        OmiaiWeb.Endpoint.broadcast("user:" <> requester.quicdial_id, "friend_accepted", %{
          "friendship_id" => friendship.id,
          "by_quicdial_id" => user.quicdial_id,
          "by_display_name" => user.display_name,
          "by_avatar_id" => user.avatar_id
        })

        OmiaiWeb.Endpoint.broadcast("peer:" <> requester.quicdial_id, "friend_accepted", %{
          "friendship_id" => friendship.id,
          "by_quicdial_id" => user.quicdial_id,
          "by_display_name" => user.display_name,
          "by_avatar_id" => user.avatar_id
        })

        json(conn, %{status: "accepted"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :unauthorized} ->
        conn |> put_status(:forbidden) |> json(%{error: "unauthorized"})
    end
  end

  def decline(conn, %{"id" => friendship_id}) do
    user = conn.assigns.current_user

    case Accounts.decline_friend_request(friendship_id, user.id) do
      {:ok, friendship} ->
        requester = Accounts.get_user!(friendship.requester_id)

        OmiaiWeb.Endpoint.broadcast("user:" <> requester.quicdial_id, "friend_declined", %{
          "friendship_id" => friendship.id,
          "by_quicdial_id" => user.quicdial_id
        })

        OmiaiWeb.Endpoint.broadcast("peer:" <> requester.quicdial_id, "friend_declined", %{
          "friendship_id" => friendship.id,
          "by_quicdial_id" => user.quicdial_id
        })

        json(conn, %{status: "declined"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, :unauthorized} ->
        conn |> put_status(:forbidden) |> json(%{error: "unauthorized"})
    end
  end

  def remove(conn, %{"quicdial_id" => quicdial_id}) do
    user = conn.assigns.current_user

    case Accounts.remove_friendship(user.id, quicdial_id) do
      :ok ->
        OmiaiWeb.Endpoint.broadcast("user:" <> quicdial_id, "friend_removed", %{
          "by_quicdial_id" => user.quicdial_id
        })

        OmiaiWeb.Endpoint.broadcast("peer:" <> quicdial_id, "friend_removed", %{
          "by_quicdial_id" => user.quicdial_id
        })

        json(conn, %{status: "removed"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end
end
