defmodule OmiaiWeb.AuthController do
  use OmiaiWeb, :controller

  alias Omiai.Accounts

  action_fallback OmiaiWeb.FallbackController

  @doc """
  Register a new user. The `quicdial_id` field is optional — if omitted,
  the server auto-generates a unique ###-###-### code.
  """
  def signup(conn, params) do
    attrs = %{
      quicdial_id: non_empty_string(params["quicdial_id"]),
      display_name: params["display_name"],
      password: params["password"],
      avatar_id: params["avatar_id"] || "kyu-kun"
    }

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        token = Accounts.generate_session_token(user)

        conn
        |> put_status(:created)
        |> json(%{
          token: token,
          user: %{
            quicdial_id: user.quicdial_id,
            display_name: user.display_name,
            avatar_id: user.avatar_id
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "signup_failed", details: errors})
    end
  end

  defp non_empty_string(nil), do: nil
  defp non_empty_string(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      trimmed -> trimmed
    end
  end
  defp non_empty_string(_), do: nil

  def login(conn, %{"quicdial_id" => quicdial_id, "password" => password}) do
    case Accounts.authenticate(quicdial_id, password) do
      {:ok, user} ->
        token = Accounts.generate_session_token(user)

        conn
        |> json(%{
          token: token,
          user: %{
            quicdial_id: user.quicdial_id,
            display_name: user.display_name,
            avatar_id: user.avatar_id
          }
        })

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_fields", details: "quicdial_id and password required"})
  end

  def me(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      user: %{
        quicdial_id: user.quicdial_id,
        display_name: user.display_name,
        avatar_id: user.avatar_id
      }
    })
  end

  @doc """
  Request a password reset token. For testing, the token is returned directly.
  In production, this would send an email instead.
  """
  def request_password_reset(conn, %{"quicdial_id" => quicdial_id}) do
    case Accounts.request_password_reset(quicdial_id) do
      {:ok, token} ->
        # In production, send email and don't return the token
        json(conn, %{
          message: "password_reset_requested",
          reset_token: token
        })

      {:error, :not_found} ->
        # Don't reveal whether the account exists — still return 200
        json(conn, %{message: "password_reset_requested"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "reset_request_failed"})
    end
  end

  def request_password_reset(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_fields", details: "quicdial_id required"})
  end

  @doc """
  Reset the password using a valid reset token and new password.
  """
  def reset_password(conn, %{"token" => token, "password" => password}) do
    case Accounts.reset_password(token, password) do
      {:ok, user} ->
        new_token = Accounts.generate_session_token(user)

        json(conn, %{
          message: "password_reset_success",
          token: new_token,
          user: %{
            quicdial_id: user.quicdial_id,
            display_name: user.display_name,
            avatar_id: user.avatar_id
          }
        })

      {:error, :invalid_token} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_token"})

      {:error, :token_expired} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "token_expired"})

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_changeset_errors(changeset)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "reset_failed", details: errors})
    end
  end

  def reset_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_fields", details: "token and password required"})
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
