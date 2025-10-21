defmodule Airdropper.AirdropWorker do
  @moduledoc """
  GenServer that manages airdrop operations.

  Handles the state and execution of airdrops, including:
  - Starting and stopping airdrops
  - Tracking progress
  - Managing transaction results
  - Pausing and resuming operations
  """

  use GenServer

  require Logger

  @type status :: :idle | :processing | :paused | :completed | :failed
  @type entry :: %{address: String.t(), amount: non_neg_integer()}
  @type progress :: %{
          total: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          percentage: float()
        }
  @type result :: %{
          address: String.t(),
          signature: String.t() | nil,
          status: :success | :failed,
          error: String.t() | nil
        }

  @type state :: %{
          status: status(),
          entries: [entry()],
          progress: progress(),
          current_transaction: entry() | nil,
          results: [result()]
        }

  # Client API

  @doc """
  Starts the AirdropWorker GenServer.

  ## Options
  - `:name` - The name to register the process under. Defaults to `__MODULE__` when
    started under supervision. Pass an empty list `[]` for unnamed instances (useful in tests).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    # Only set default name if opts is empty (supervision tree case)
    # If opts has any value (even [name: nil]), respect it
    opts = if opts == [], do: [name: __MODULE__], else: opts
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Gets the current state of the worker.
  """
  @spec get_state(pid()) :: state()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Starts an airdrop with the given entries.
  """
  @spec start_airdrop(pid(), [entry()]) :: :ok | {:error, atom()}
  def start_airdrop(pid, entries) do
    GenServer.call(pid, {:start_airdrop, entries})
  end

  @doc """
  Pauses the currently running airdrop.
  """
  @spec pause_airdrop(pid()) :: :ok | {:error, atom()}
  def pause_airdrop(pid) do
    GenServer.call(pid, :pause_airdrop)
  end

  @doc """
  Resumes a paused airdrop.
  """
  @spec resume_airdrop(pid()) :: :ok | {:error, atom()}
  def resume_airdrop(pid) do
    GenServer.call(pid, :resume_airdrop)
  end

  @doc """
  Gets the current status of the worker.
  """
  @spec get_status(pid()) :: status()
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Gets the current progress of the airdrop.
  """
  @spec get_progress(pid()) :: progress()
  def get_progress(pid) do
    GenServer.call(pid, :get_progress)
  end

  @doc """
  Resets the worker to its initial state.
  """
  @spec reset(pid()) :: :ok
  def reset(pid) do
    GenServer.call(pid, :reset)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    {:ok, initial_state()}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:start_airdrop, entries}, _from, state) do
    cond do
      state.status in [:processing, :paused] ->
        {:reply, {:error, :already_processing}, state}

      entries == [] ->
        {:reply, {:error, :empty_entries}, state}

      true ->
        new_state = %{
          state
          | status: :processing,
            entries: entries,
            progress: %{
              total: length(entries),
              completed: 0,
              failed: 0,
              percentage: 0.0
            },
            results: []
        }

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:pause_airdrop, _from, state) do
    if state.status == :processing do
      {:reply, :ok, %{state | status: :paused}}
    else
      {:reply, {:error, :not_processing}, state}
    end
  end

  @impl true
  def handle_call(:resume_airdrop, _from, state) do
    if state.status == :paused do
      {:reply, :ok, %{state | status: :processing}}
    else
      {:reply, {:error, :not_paused}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_call(:get_progress, _from, state) do
    {:reply, state.progress, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, initial_state()}
  end

  # Private Functions

  defp initial_state do
    %{
      status: :idle,
      entries: [],
      progress: %{
        total: 0,
        completed: 0,
        failed: 0,
        percentage: 0.0
      },
      current_transaction: nil,
      results: []
    }
  end
end
