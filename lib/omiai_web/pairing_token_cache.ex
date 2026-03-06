defmodule OmiaiWeb.PairingTokenCache do
  @moduledoc """
  Mock token cache for QR code pairing. Maps pairing tokens to quicdial_ids.
  Tokens are one-time use and expire after TTL.
  """

  use GenServer

  @table __MODULE__
  @ttl_seconds 300
  @token_length 6

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Generates a new pairing token for the given quicdial_id.
  Returns a 6-digit token string.
  """
  @spec generate(String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate(quicdial_id) when is_binary(quicdial_id) do
    token = generate_token()
    GenServer.call(__MODULE__, {:store, token, String.trim(quicdial_id)})
  end

  @doc """
  Validates a pairing token and returns the associated quicdial_id.
  Consumes the token (one-time use).
  """
  @spec validate(String.t()) :: {:ok, String.t()} | {:error, :invalid | :expired}
  def validate(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:validate, String.trim(token)})
  end

  defp generate_token do
    1..@token_length
    |> Enum.map(fn _ -> Enum.random(?0..?9) end)
    |> to_string()
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  @impl true
  def handle_call({:store, token, quicdial_id}, _from, state) do
    expires_at = System.system_time(:second) + @ttl_seconds
    :ets.insert(@table, {token, quicdial_id, expires_at})
    {:reply, {:ok, token}, state}
  end

  @impl true
  def handle_call({:validate, token}, _from, state) do
    now = System.system_time(:second)

    result =
      case :ets.lookup(@table, token) do
        [{^token, quicdial_id, expires_at}] ->
          :ets.delete(@table, token)

          if expires_at >= now do
            {:ok, quicdial_id}
          else
            {:error, :expired}
          end

        [] ->
          {:error, :invalid}
      end

    {:reply, result, state}
  end
end
