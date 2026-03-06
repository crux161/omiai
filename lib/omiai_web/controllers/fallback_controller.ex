defmodule OmiaiWeb.FallbackController do
  use OmiaiWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_failed", details: errors})
  end
end
