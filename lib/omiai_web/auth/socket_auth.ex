defmodule OmiaiWeb.Auth.SocketAuth do
  @moduledoc """
  Authentication stub for websocket signaling clients.

  NOTE: This module currently validates shape/required fields only.
  The cryptographic ownership verification is intentionally stubbed and should
  be implemented where noted in `authenticate/2`.
  """

  @valid_event_contracts ~w(sdp legacy dual)

  @type auth_reason :: :missing_public_key | :invalid_public_key | :invalid_event_contract

  @spec authenticate(map(), map() | nil) ::
          {:ok,
           %{
             public_key: String.t(),
             event_contract: String.t(),
             session_token: String.t() | nil,
             signature: String.t() | nil,
             sig_ts: String.t() | nil,
             sig_nonce: String.t() | nil,
             client_meta: map()
           }}
          | {:error, auth_reason()}
  def authenticate(params, connect_info) when is_map(params) do
    with {:ok, public_key} <- fetch_public_key(params),
         {:ok, event_contract} <- normalize_event_contract(Map.get(params, "event_contract")) do
      claims = %{
        public_key: public_key,
        event_contract: event_contract,
        session_token: optional_string(Map.get(params, "session_token")),
        signature: optional_string(Map.get(params, "signature")),
        sig_ts: optional_string(Map.get(params, "sig_ts")),
        sig_nonce: optional_string(Map.get(params, "sig_nonce")),
        client_meta: extract_client_meta(connect_info || %{})
      }

      # TODO(crypto-verification): verify `signature` ownership proof using
      # canonical message {public_key, session_token, sig_ts, sig_nonce}.
      # Reject replayed requests by validating timestamp window and nonce reuse,
      # and reject if signature public key does not match requested `public_key`.
      {:ok, claims}
    end
  end

  def authenticate(_params, _connect_info), do: {:error, :missing_public_key}

  defp fetch_public_key(params) do
    value = params |> Map.get("public_key") |> optional_string()

    cond do
      is_nil(value) ->
        {:error, :missing_public_key}

      valid_public_key?(value) ->
        {:ok, value}

      true ->
        {:error, :invalid_public_key}
    end
  end

  defp normalize_event_contract(nil), do: {:ok, "dual"}

  defp normalize_event_contract(value) do
    normalized = value |> to_string() |> String.trim() |> String.downcase()

    if normalized in @valid_event_contracts do
      {:ok, normalized}
    else
      {:error, :invalid_event_contract}
    end
  end

  defp valid_public_key?(key) do
    Regex.match?(~r/^[A-Za-z0-9_:\-\.\/=+]{3,512}$/, key)
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
