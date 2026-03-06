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

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
