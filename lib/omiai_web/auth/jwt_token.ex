defmodule OmiaiWeb.Auth.JwtToken do
  @moduledoc """
  Stateless JWT verification using Joken.

  The external Python service issues JWTs signed with a shared HS256 secret.
  Omiai trusts these tokens without any database lookup.

  Expected JWT claims:
    - "sub"          — user ID (string)
    - "quicdial_id"  — calling code (string, required)
    - "display_name" — display name (string)
    - "avatar_id"    — avatar identifier (string)
    - "exp"          — expiration (unix timestamp)
  """

  use Joken.Config

  @impl true
  def token_config do
    # Tokens issued by omiai-api intentionally omit iat/iss/aud/jti/nbf.
    default_claims(skip: [:aud, :iat, :iss, :jti, :nbf])
    |> add_claim("quicdial_id", nil, &is_binary/1)
  end

  @doc """
  Verify and validate a JWT string using the configured shared secret.

  Returns `{:ok, claims}` or `{:error, reason}`.
  """
  @spec verify_token(String.t()) :: {:ok, map()} | {:error, atom() | Keyword.t()}
  def verify_token(token) when is_binary(token) do
    case signer() do
      {:ok, signer} ->
        verify_and_validate(token, signer)

      :error ->
        {:error, :jwt_secret_not_configured}
    end
  end

  def verify_token(_), do: {:error, :invalid_token}

  defp signer do
    case Application.get_env(:omiai, :jwt_secret) do
      nil -> :error
      "" -> :error
      secret when is_binary(secret) -> {:ok, Joken.Signer.create("HS256", secret)}
    end
  end
end
