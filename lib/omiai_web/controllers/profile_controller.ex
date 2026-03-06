defmodule OmiaiWeb.ProfileController do
  use OmiaiWeb, :controller

  alias Omiai.Accounts

  action_fallback OmiaiWeb.FallbackController

  def show(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      user: %{
        quicdial_id: user.quicdial_id,
        display_name: user.display_name,
        avatar_id: user.avatar_id
      }
    })
  end

  def update(conn, params) do
    user = conn.assigns.current_user

    attrs =
      params
      |> Map.take(["display_name", "avatar_id"])
      |> Enum.into(%{}, fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Accounts.update_profile(user, attrs) do
      {:ok, updated} ->
        json(conn, %{
          user: %{
            quicdial_id: updated.quicdial_id,
            display_name: updated.display_name,
            avatar_id: updated.avatar_id
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "update_failed", details: errors})
    end
  end
end
