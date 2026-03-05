defmodule OmiaiWeb.QuicdialRegistry do
  @moduledoc """
  Runtime registry that maps Quicdial codes (public keys) to the latest
  observed peer IP while the peer socket process is alive.
  """

  use GenServer

  @table __MODULE__

  @type code :: String.t()
  @type ip :: String.t()
  @type state :: %{optional(pid()) => code()}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec register(code(), ip(), pid()) :: :ok
  def register(code, ip, pid \\ self()) when is_binary(code) and is_binary(ip) and is_pid(pid) do
    GenServer.call(__MODULE__, {:register, String.trim(code), String.trim(ip), pid})
  end

  @spec resolve(code()) :: {:ok, ip()} | :error
  def resolve(code) when is_binary(code) do
    normalized = String.trim(code)

    case :ets.lookup(@table, normalized) do
      [{^normalized, ip, _pid}] when is_binary(ip) and ip != "" -> {:ok, ip}
      _ -> :error
    end
  end

  @spec unregister(pid()) :: :ok
  def unregister(pid \\ self()) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:unregister, pid})
  end

  @impl true
  def init(state) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, state}
  end

  @impl true
  def handle_call({:register, code, ip, pid}, _from, state) do
    Process.monitor(pid)

    state =
      case Map.get(state, pid) do
        nil ->
          state

        existing_code ->
          maybe_delete_entry(existing_code, pid)
          state
      end

    :ets.insert(@table, {code, ip, pid})
    {:reply, :ok, Map.put(state, pid, code)}
  end

  @impl true
  def handle_cast({:unregister, pid}, state) do
    {:noreply, drop_pid(pid, state)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, drop_pid(pid, state)}
  end

  defp drop_pid(pid, state) do
    case Map.pop(state, pid) do
      {nil, next_state} ->
        next_state

      {code, next_state} ->
        maybe_delete_entry(code, pid)
        next_state
    end
  end

  defp maybe_delete_entry(code, pid) do
    case :ets.lookup(@table, code) do
      [{^code, _ip, ^pid}] -> :ets.delete(@table, code)
      _ -> :ok
    end
  end
end
