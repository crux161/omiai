defmodule OmiaiWeb.Auth.SocketAuth do
  @moduledoc """
  Authentication for multi-device WebRTC signaling connections.

  Supports (in priority order):
  - JWT auth: auth_token (JWT) + device_uuid (externally authenticated user)
  - Pairing auth: pairing_token + device_uuid (QR code flow)
  - Direct auth: quicdial_id/public_key + device_uuid (LAN fallback)
  """

  alias OmiaiWeb.Auth.JwtToken
  alias OmiaiWeb.PairingTokenCache

  @valid_quicdial_pattern ~r/^[A-Za-z0-9_:\-\.\/=+]{3,512}$/
  @valid_device_uuid_pattern ~r/^[A-Za-z0-9\-]{8,64}$/

  @type auth_reason ::
          :missing_quicdial_id
          | :missing_device_uuid
          | :invalid_quicdial_id
          | :invalid_device_uuid
          | :invalid_pairing_token
          | :pairing_token_expired
          | :invalid_auth_token
          | :jwt_secret_not_configured

  @spec authenticate(map(), map() | nil) ::
          {:ok,
           %{
             quicdial_id: String.t(),
             device_uuid: String.t(),
             user_id: String.t() | nil,
             display_name: String.t() | nil,
             avatar_id: String.t() | nil,
             client_meta: map()
           }}
          | {:error, auth_reason()}
  def authenticate(params, connect_info) when is_map(params) do
    cond do
      # JWT flow: auth_token is a JWT issued by the Python backend
      Map.has_key?(params, "auth_token") or Map.has_key?(params, :auth_token) ->
        authenticate_jwt(params, connect_info)

      # Pairing flow: pairing_token + device_uuid
      Map.has_key?(params, "pairing_token") or Map.has_key?(params, :pairing_token) ->
        authenticate_pairing(params, connect_info)

      # Direct flow: quicdial_id / public_key + device_uuid (LAN fallback)
      true ->
        authenticate_direct(params, connect_info)
    end
  end

  def authenticate(_params, _connect_info), do: {:error, :missing_quicdial_id}

  defp authenticate_jwt(params, connect_info) do
    token = optional_string(params["auth_token"] || params[:auth_token])

    case JwtToken.verify_token(token || "") do
      {:ok, claims} ->
        {:ok, device_uuid} = fetch_device_uuid(params)

        {:ok,
         %{
           quicdial_id: claims["quicdial_id"],
           device_uuid: device_uuid,
           user_id: claims["sub"],
           display_name: claims["display_name"],
           avatar_id: claims["avatar_id"],
           client_meta: extract_client_meta(connect_info || %{})
         }}

      {:error, _reason} ->
        {:error, :invalid_auth_token}
    end
  end

  defp authenticate_direct(params, connect_info) do
    with {:ok, quicdial_id} <- fetch_quicdial_id(params),
         {:ok, device_uuid} <- fetch_device_uuid(params) do
      {:ok,
       %{
         quicdial_id: quicdial_id,
         device_uuid: device_uuid,
         user_id: nil,
         display_name: nil,
         avatar_id: nil,
         client_meta: extract_client_meta(connect_info || %{})
       }}
    end
  end

  defp authenticate_pairing(params, connect_info) do
    with {:ok, token} <- fetch_pairing_token(params),
         {:ok, device_uuid} <- fetch_device_uuid(params),
         {:ok, quicdial_id} <- PairingTokenCache.validate(token) do
      {:ok,
       %{
         quicdial_id: quicdial_id,
         device_uuid: device_uuid,
         user_id: nil,
         display_name: nil,
         avatar_id: nil,
         client_meta: extract_client_meta(connect_info || %{})
       }}
    else
      {:error, :invalid} -> {:error, :invalid_pairing_token}
      {:error, :expired} -> {:error, :pairing_token_expired}
      other -> other
    end
  end

  defp fetch_quicdial_id(params) do
    value =
      optional_string(
        params["quicdial_id"] || params[:quicdial_id] ||
          params["public_key"] || params[:public_key]
      )

    cond do
      is_nil(value) or value == "" -> {:error, :missing_quicdial_id}
      Regex.match?(@valid_quicdial_pattern, value) -> {:ok, value}
      true -> {:error, :invalid_quicdial_id}
    end
  end

  defp fetch_device_uuid(params) do
    value = optional_string(params["device_uuid"] || params[:device_uuid])

    cond do
      is_nil(value) or value == "" ->
        generate_device_uuid(params)

      Regex.match?(@valid_device_uuid_pattern, value) ->
        {:ok, value}

      true ->
        {:error, :invalid_device_uuid}
    end
  end

  defp generate_device_uuid(params) do
    seed =
      optional_string(params["session_token"] || params[:session_token]) ||
        optional_string(params["sig_nonce"] || params[:sig_nonce])

    uuid =
      if seed do
        :crypto.hash(:sha256, seed)
        |> Base.encode16(case: :lower)
        |> binary_part(0, 32)
        |> format_as_uuid()
      else
        :crypto.strong_rand_bytes(16)
        |> Base.encode16(case: :lower)
        |> format_as_uuid()
      end

    {:ok, uuid}
  end

  defp format_as_uuid(
         <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
           e::binary-size(12)>>
       ) do
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  defp fetch_pairing_token(params) do
    value = optional_string(params["pairing_token"] || params[:pairing_token])

    if is_nil(value) or value == "" do
      {:error, :invalid_pairing_token}
    else
      {:ok, value}
    end
  end

  defp optional_string(nil), do: nil

  defp optional_string(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp extract_client_meta(connect_info) when is_map(connect_info) do
    peer_data = Map.get(connect_info, :peer_data) || Map.get(connect_info, "peer_data") || %{}

    %{
      ip: peer_ip(peer_data),
      port: Map.get(peer_data, :port),
      user_agent: extract_user_agent(connect_info),
      uri: extract_uri(connect_info)
    }
  end

  defp extract_client_meta(_), do: %{ip: nil, port: nil, user_agent: nil, uri: nil}

  defp peer_ip(%{address: address}) when is_tuple(address) do
    case :inet.ntoa(address) do
      {:error, _} -> nil
      ip -> to_string(ip)
    end
  end

  defp peer_ip(_), do: nil

  defp extract_user_agent(connect_info) do
    headers = Map.get(connect_info, :x_headers) || Map.get(connect_info, "x_headers") || []

    Enum.find_value(headers, fn
      {key, value} when is_binary(key) ->
        if String.downcase(key) == "user-agent", do: to_string(value), else: nil

      {key, value} ->
        key_string = key |> to_string() |> String.downcase()
        if key_string == "user-agent", do: to_string(value), else: nil

      _ ->
        nil
    end)
  end

  defp extract_uri(connect_info) do
    case Map.get(connect_info, :uri) || Map.get(connect_info, "uri") do
      %URI{} = uri -> URI.to_string(uri)
      _ -> nil
    end
  end
end
