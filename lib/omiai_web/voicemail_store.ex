defmodule OmiaiWeb.VoicemailStore do
  @moduledoc """
  ETS-backed voicemail store for offline message delivery.

  Voicemails are stored temporarily (TTL: 7 days) and cleaned up periodically.
  Size limit: 10MB per voicemail.
  """

  use GenServer

  require Logger

  @table :voicemail_store
  @ttl_ms 7 * 24 * 60 * 60 * 1000
  @max_size_bytes 10 * 1024 * 1024
  @cleanup_interval_ms 60 * 60 * 1000

  # -------------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Deposit a voicemail for a recipient."
  @spec deposit(String.t(), String.t(), String.t(), map()) ::
          {:ok, String.t()} | {:error, String.t()}
  def deposit(to_quicdial_id, from_quicdial_id, data_b64, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:deposit, to_quicdial_id, from_quicdial_id, data_b64, metadata})
  end

  @doc "Check pending voicemails for a recipient."
  @spec check(String.t()) :: [map()]
  def check(quicdial_id) do
    GenServer.call(__MODULE__, {:check, quicdial_id})
  end

  @doc "Fetch a specific voicemail by ID (only if it belongs to the requester)."
  @spec fetch(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def fetch(voicemail_id, quicdial_id) do
    GenServer.call(__MODULE__, {:fetch, voicemail_id, quicdial_id})
  end

  @doc "Delete a specific voicemail by ID (only if it belongs to the requester)."
  @spec delete(String.t(), String.t()) :: :ok | {:error, String.t()}
  def delete(voicemail_id, quicdial_id) do
    GenServer.call(__MODULE__, {:delete, voicemail_id, quicdial_id})
  end

  # -------------------------------------------------------------------------
  # GenServer callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :private])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:deposit, to_id, from_id, data_b64, metadata}, _from, state) do
    size = byte_size(data_b64)

    if size > @max_size_bytes do
      {:reply, {:error, "voicemail_too_large"}, state}
    else
      id = generate_id()
      now = System.system_time(:millisecond)

      entry = %{
        id: id,
        to_quicdial_id: to_id,
        from_quicdial_id: from_id,
        data_b64: data_b64,
        metadata: metadata,
        inserted_at: now
      }

      :ets.insert(@table, {id, entry})
      Logger.info("voicemail_deposited id=#{id} from=#{from_id} to=#{to_id} size=#{size}")
      {:reply, {:ok, id}, state}
    end
  end

  @impl true
  def handle_call({:check, quicdial_id}, _from, state) do
    now = System.system_time(:millisecond)

    entries =
      :ets.tab2list(@table)
      |> Enum.map(fn {_key, entry} -> entry end)
      |> Enum.filter(fn entry ->
        entry.to_quicdial_id == quicdial_id && now - entry.inserted_at < @ttl_ms
      end)
      |> Enum.sort_by(& &1.inserted_at)
      |> Enum.map(fn entry ->
        %{
          id: entry.id,
          from_quicdial_id: entry.from_quicdial_id,
          metadata: entry.metadata,
          inserted_at: entry.inserted_at
        }
      end)

    {:reply, entries, state}
  end

  @impl true
  def handle_call({:fetch, voicemail_id, quicdial_id}, _from, state) do
    case :ets.lookup(@table, voicemail_id) do
      [{^voicemail_id, entry}] ->
        if entry.to_quicdial_id == quicdial_id do
          {:reply, {:ok, entry}, state}
        else
          {:reply, {:error, "unauthorized"}, state}
        end

      [] ->
        {:reply, {:error, "not_found"}, state}
    end
  end

  @impl true
  def handle_call({:delete, voicemail_id, quicdial_id}, _from, state) do
    case :ets.lookup(@table, voicemail_id) do
      [{^voicemail_id, entry}] ->
        if entry.to_quicdial_id == quicdial_id do
          :ets.delete(@table, voicemail_id)
          {:reply, :ok, state}
        else
          {:reply, {:error, "unauthorized"}, state}
        end

      [] ->
        {:reply, {:error, "not_found"}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:millisecond)

    expired =
      :ets.tab2list(@table)
      |> Enum.filter(fn {_key, entry} -> now - entry.inserted_at >= @ttl_ms end)

    for {key, _entry} <- expired do
      :ets.delete(@table, key)
    end

    if length(expired) > 0 do
      Logger.info("voicemail_cleanup expired=#{length(expired)}")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # -------------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------------

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
