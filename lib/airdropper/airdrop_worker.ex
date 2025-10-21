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

  @pubsub_topic "airdrop:progress"

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
          results: [result()],
          expected_completions: non_neg_integer() | nil
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

  @doc """
  Processes entries in batches using Task.Supervisor for concurrent execution.

  ## Options
  - `:max_concurrency` - Maximum number of concurrent tasks (default: 10)
  - `:timeout` - Timeout for each task in milliseconds (default: 30_000)
  - `:task_supervisor` - Name of the Task.Supervisor to use (default: Airdropper.TaskSupervisor)
  """
  @spec process_batch(pid(), fun(), keyword()) :: :ok | {:error, atom()}
  def process_batch(pid, process_fn, opts \\ []) do
    GenServer.call(pid, {:process_batch, process_fn, opts}, :infinity)
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

        # Broadcast airdrop started
        broadcast({:airdrop_started, %{total: length(entries)}})

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

  @impl true
  def handle_call({:process_batch, process_fn, opts}, _from, state) do
    if state.status != :processing do
      {:reply, {:error, :not_processing}, state}
    else
      # Process entries concurrently
      max_concurrency = Keyword.get(opts, :max_concurrency, 10)
      timeout = Keyword.get(opts, :timeout, 30_000)
      task_supervisor_name = Keyword.get(opts, :task_supervisor, Airdropper.TaskSupervisor)

      # Start async processing in a separate process to not block the GenServer
      parent = self()

      Task.start(fn ->
        # Collect all results first (forces stream evaluation)
        results =
          Task.Supervisor.async_stream_nolink(
            task_supervisor_name,
            state.entries,
            fn entry ->
              process_entry(entry, process_fn, timeout)
            end,
            max_concurrency: max_concurrency,
            timeout: timeout,
            on_timeout: :kill_task
          )
          |> Enum.to_list()

        # Tell GenServer how many completions to expect
        GenServer.cast(parent, {:batch_starting, length(results)})

        # Now send all task completions asynchronously
        results
        |> Enum.zip(state.entries)
        |> Enum.each(fn
          {{:ok, {:ok, signature, entry}}, _} ->
            GenServer.cast(parent, {:task_completed, {:ok, signature, entry}})

          {{:ok, {:error, error, entry}}, _} ->
            GenServer.cast(parent, {:task_completed, {:error, error, entry}})

          {{:exit, reason}, entry} ->
            error_result = {:error, "timeout: #{inspect(reason)}", entry}
            GenServer.cast(parent, {:task_completed, error_result})
        end)
      end)

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:batch_starting, expected_count}, state) do
    {:noreply, %{state | expected_completions: expected_count}}
  end

  @impl true
  def handle_cast({:task_completed, {:ok, signature, entry}}, state) do
    new_result = %{
      address: entry.address,
      signature: signature,
      status: :success,
      error: nil
    }

    new_completed = state.progress.completed + 1

    new_progress = %{
      state.progress
      | completed: new_completed,
        percentage:
          calculate_percentage(new_completed + state.progress.failed, state.progress.total)
    }

    # Broadcast individual transfer completion
    broadcast({:transfer_completed, new_result})

    new_state = %{
      state
      | progress: new_progress,
        results: [new_result | state.results],
        current_transaction: nil
    }

    # Check if all tasks are complete
    check_and_complete_batch(new_state)
  end

  @impl true
  def handle_cast({:task_completed, {:error, error, entry}}, state) do
    new_result = %{
      address: entry.address,
      signature: nil,
      status: :failed,
      error: error
    }

    new_failed = state.progress.failed + 1

    new_progress = %{
      state.progress
      | failed: new_failed,
        percentage:
          calculate_percentage(state.progress.completed + new_failed, state.progress.total)
    }

    # Broadcast individual transfer failure
    broadcast({:transfer_completed, new_result})

    new_state = %{
      state
      | progress: new_progress,
        results: [new_result | state.results],
        current_transaction: nil
    }

    # Check if all tasks are complete
    check_and_complete_batch(new_state)
  end

  @impl true
  def terminate(_reason, state) do
    # Graceful shutdown - let ongoing tasks complete
    if state.status == :processing do
      Logger.info("AirdropWorker terminating, waiting for tasks to complete...")
      # Give tasks a brief moment to finish
      Process.sleep(1000)
    end

    :ok
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
      results: [],
      expected_completions: nil
    }
  end

  defp process_entry(entry, process_fn, _timeout) do
    try do
      case process_fn.(entry) do
        {:ok, signature} -> {:ok, signature, entry}
        {:error, reason} -> {:error, reason, entry}
        other -> {:error, "unexpected_return: #{inspect(other)}", entry}
      end
    catch
      kind, reason ->
        {:error, "#{kind}: #{inspect(reason)}", entry}
    end
  end

  defp calculate_percentage(completed, total) when total > 0 do
    Float.round(completed / total * 100, 2)
  end

  defp calculate_percentage(_completed, 0), do: 0.0

  defp check_and_complete_batch(state) do
    total_processed = state.progress.completed + state.progress.failed

    if state.expected_completions != nil and total_processed == state.expected_completions do
      # All tasks completed!
      new_status = if state.progress.failed > 0, do: :completed, else: :completed
      completed_state = %{state | status: new_status, expected_completions: nil}

      # Broadcast final progress update
      broadcast({:airdrop_progress, completed_state.progress})

      # Broadcast final completion
      broadcast({:airdrop_completed, completed_state})

      {:noreply, completed_state}
    else
      {:noreply, state}
    end
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Airdropper.PubSub, @pubsub_topic, message)
  end
end
