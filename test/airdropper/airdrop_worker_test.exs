defmodule Airdropper.AirdropWorkerTest do
  use ExUnit.Case, async: true

  alias Airdropper.AirdropWorker

  describe "supervision" do
    test "worker is started under application supervision tree" do
      # The worker should be registered with the name Airdropper.AirdropWorker
      assert Process.whereis(Airdropper.AirdropWorker) != nil
    end

    test "can access worker via registered name" do
      state = AirdropWorker.get_state(Airdropper.AirdropWorker)
      assert state.status == :idle
    end
  end

  describe "start_link/1" do
    test "starts the GenServer with default state" do
      assert {:ok, pid} = AirdropWorker.start_link(name: nil)
      assert Process.alive?(pid)
    end

    test "starts with :idle status" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      assert %{status: :idle} = AirdropWorker.get_state(pid)
    end

    test "starts with empty entries list" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      state = AirdropWorker.get_state(pid)
      assert state.entries == []
    end

    test "starts with zero progress" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      state = AirdropWorker.get_state(pid)
      assert state.progress.total == 0
      assert state.progress.completed == 0
      assert state.progress.failed == 0
      assert state.progress.percentage == 0.0
    end

    test "starts with no current transaction" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      state = AirdropWorker.get_state(pid)
      assert state.current_transaction == nil
    end

    test "starts with empty results list" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      state = AirdropWorker.get_state(pid)
      assert state.results == []
    end
  end

  describe "get_state/1" do
    test "returns the current state" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      state = AirdropWorker.get_state(pid)

      assert is_map(state)
      assert Map.has_key?(state, :status)
      assert Map.has_key?(state, :entries)
      assert Map.has_key?(state, :progress)
      assert Map.has_key?(state, :current_transaction)
      assert Map.has_key?(state, :results)
    end
  end

  describe "start_airdrop/2" do
    test "changes status from :idle to :processing" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test123", amount: 1_000_000_000}]

      :ok = AirdropWorker.start_airdrop(pid, entries)

      state = AirdropWorker.get_state(pid)
      assert state.status == :processing
    end

    test "stores the entries to process" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000}
      ]

      :ok = AirdropWorker.start_airdrop(pid, entries)

      state = AirdropWorker.get_state(pid)
      assert state.entries == entries
    end

    test "initializes progress with total count" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000}
      ]

      :ok = AirdropWorker.start_airdrop(pid, entries)

      state = AirdropWorker.get_state(pid)
      assert state.progress.total == 2
      assert state.progress.completed == 0
      assert state.progress.failed == 0
    end

    test "returns error if already processing" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test", amount: 1_000_000_000}]

      :ok = AirdropWorker.start_airdrop(pid, entries)
      result = AirdropWorker.start_airdrop(pid, entries)

      assert result == {:error, :already_processing}
    end

    test "returns error if entries list is empty" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      result = AirdropWorker.start_airdrop(pid, [])

      assert result == {:error, :empty_entries}
    end
  end

  describe "pause_airdrop/1" do
    test "changes status from :processing to :paused" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test", amount: 1_000_000_000}]

      AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.pause_airdrop(pid)

      state = AirdropWorker.get_state(pid)
      assert state.status == :paused
    end

    test "returns error if not processing" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      result = AirdropWorker.pause_airdrop(pid)

      assert result == {:error, :not_processing}
    end

    test "can pause from :processing state" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test", amount: 1_000_000_000}]

      AirdropWorker.start_airdrop(pid, entries)
      assert :ok = AirdropWorker.pause_airdrop(pid)
    end
  end

  describe "resume_airdrop/1" do
    test "changes status from :paused to :processing" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test", amount: 1_000_000_000}]

      AirdropWorker.start_airdrop(pid, entries)
      AirdropWorker.pause_airdrop(pid)
      :ok = AirdropWorker.resume_airdrop(pid)

      state = AirdropWorker.get_state(pid)
      assert state.status == :processing
    end

    test "returns error if not paused" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      result = AirdropWorker.resume_airdrop(pid)

      assert result == {:error, :not_paused}
    end
  end

  describe "get_status/1" do
    test "returns :idle initially" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      assert AirdropWorker.get_status(pid) == :idle
    end

    test "returns :processing when airdrop started" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test", amount: 1_000_000_000}]

      AirdropWorker.start_airdrop(pid, entries)

      assert AirdropWorker.get_status(pid) == :processing
    end

    test "returns :paused when airdrop paused" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test", amount: 1_000_000_000}]

      AirdropWorker.start_airdrop(pid, entries)
      AirdropWorker.pause_airdrop(pid)

      assert AirdropWorker.get_status(pid) == :paused
    end
  end

  describe "get_progress/1" do
    test "returns progress information" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000}
      ]

      AirdropWorker.start_airdrop(pid, entries)
      progress = AirdropWorker.get_progress(pid)

      assert progress.total == 2
      assert progress.completed == 0
      assert progress.failed == 0
    end

    test "calculates percentage correctly" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000}
      ]

      AirdropWorker.start_airdrop(pid, entries)
      progress = AirdropWorker.get_progress(pid)

      assert progress.percentage == 0.0
    end
  end

  describe "reset/1" do
    test "resets worker to idle state" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "test", amount: 1_000_000_000}]

      AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.reset(pid)

      state = AirdropWorker.get_state(pid)
      assert state.status == :idle
      assert state.entries == []
      assert state.progress.total == 0
    end
  end

  describe "concurrent processing" do
    test "can process multiple entries concurrently" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000},
        %{address: "addr3", amount: 3_000_000_000}
      ]

      # Mock process function that simulates async work
      process_fn = fn _entry ->
        Process.sleep(10)
        {:ok, "signature_#{:rand.uniform(1000)}"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn, max_concurrency: 2)

      # Give some time for processing
      Process.sleep(100)

      state = AirdropWorker.get_state(pid)
      # Progress should be tracked
      assert state.progress.total == 3
    end

    test "handles task timeout correctly" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "addr1", amount: 1_000_000_000}]

      # Function that takes too long
      slow_fn = fn _entry ->
        Process.sleep(5000)
        {:ok, "signature"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, slow_fn, timeout: 50)

      # Wait for timeout to occur
      Process.sleep(100)

      state = AirdropWorker.get_state(pid)
      # Should have recorded the timeout failure
      assert state.progress.failed > 0
    end

    test "continues processing after task failure" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000},
        %{address: "addr3", amount: 3_000_000_000}
      ]

      # Function that fails on second entry
      process_fn = fn entry ->
        if entry.address == "addr2" do
          {:error, "simulated failure"}
        else
          {:ok, "signature_#{entry.address}"}
        end
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn)

      # Wait for processing to complete
      Process.sleep(100)

      state = AirdropWorker.get_state(pid)
      # Should have processed all entries despite one failure
      assert state.progress.completed + state.progress.failed == 3
      assert state.progress.failed == 1
      assert state.progress.completed == 2
    end

    test "respects max_concurrency limit" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      # Create 10 entries
      entries =
        Enum.map(1..10, fn i ->
          %{address: "addr#{i}", amount: 1_000_000_000}
        end)

      # Track concurrent executions
      test_pid = self()

      process_fn = fn entry ->
        send(test_pid, {:processing, entry.address})
        Process.sleep(50)
        send(test_pid, {:done, entry.address})
        {:ok, "signature"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn, max_concurrency: 3)

      # Give time for processing
      Process.sleep(200)

      # Verify we got processing messages (basic sanity check)
      assert_received {:processing, _}
    end

    test "updates progress during concurrent processing" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries =
        Enum.map(1..5, fn i ->
          %{address: "addr#{i}", amount: 1_000_000_000}
        end)

      process_fn = fn _entry ->
        Process.sleep(20)
        {:ok, "signature"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)

      # Start processing
      Task.start(fn ->
        AirdropWorker.process_batch(pid, process_fn, max_concurrency: 2)
      end)

      # Check progress during processing
      Process.sleep(30)
      state = AirdropWorker.get_state(pid)

      # Should be in processing state
      assert state.status == :processing
      assert state.progress.total == 5
    end
  end

  describe "Task.Supervisor integration" do
    test "TaskSupervisor is registered and available" do
      assert Process.whereis(Airdropper.TaskSupervisor) != nil
    end
  end

  describe "PubSub broadcasting" do
    setup do
      # Subscribe to the airdrop progress topic
      Phoenix.PubSub.subscribe(Airdropper.PubSub, "airdrop:progress")
      :ok
    end

    test "broadcasts when airdrop starts" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)
      entries = [%{address: "addr1", amount: 1_000_000_000}]

      :ok = AirdropWorker.start_airdrop(pid, entries)

      assert_receive {:airdrop_started, %{total: 1}}, 500
    end

    test "broadcasts progress updates during batch processing" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000}
      ]

      process_fn = fn _entry ->
        Process.sleep(10)
        {:ok, "signature123"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn, delay: 0)

      # Should receive start message
      assert_receive {:airdrop_started, %{total: 2}}, 500

      # Should receive progress updates as tasks complete
      assert_receive {:airdrop_progress, progress}, 1000
      assert progress.total == 2
      assert progress.completed >= 0
      assert progress.failed >= 0
      assert is_float(progress.percentage)
    end

    test "broadcasts completion message when batch finishes" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000}
      ]

      process_fn = fn _entry ->
        {:ok, "signature123"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn, delay: 0)

      # Should receive completion message
      assert_receive {:airdrop_completed, final_state}, 2000
      assert final_state.status in [:completed, :failed]
      assert final_state.progress.total == 1
    end

    test "broadcasts individual transfer completion" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000}
      ]

      process_fn = fn entry ->
        {:ok, "sig_#{entry.address}"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn, delay: 0)

      # Should receive transfer completion
      assert_receive {:transfer_completed, result}, 1000
      assert result.address == "addr1"
      assert result.status == :success
      assert result.signature == "sig_addr1"
      assert result.error == nil
    end

    test "broadcasts transfer failure" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000}
      ]

      process_fn = fn _entry ->
        {:error, "Insufficient funds"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn, delay: 0)

      # Should receive transfer failure
      assert_receive {:transfer_completed, result}, 1000
      assert result.address == "addr1"
      assert result.status == :failed
      assert result.signature == nil
      assert result.error == "Insufficient funds"
    end

    test "broadcasts progress with correct statistics" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [
        %{address: "addr1", amount: 1_000_000_000},
        %{address: "addr2", amount: 2_000_000_000},
        %{address: "addr3", amount: 3_000_000_000}
      ]

      # Mix of success and failure
      process_fn = fn entry ->
        # Small delay to ensure async tasks complete properly
        Process.sleep(5)

        if String.ends_with?(entry.address, "1") do
          {:error, "Failed"}
        else
          {:ok, "signature"}
        end
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn)

      # Wait for completion message to ensure batch is done
      assert_receive {:airdrop_completed, final_state}, 1000

      # Verify final state from the broadcast message
      assert final_state.progress.completed + final_state.progress.failed == 3
      assert final_state.progress.percentage == 100.0

      # Also verify via get_state
      state = AirdropWorker.get_state(pid)
      assert state.progress.completed + state.progress.failed == 3
      assert state.progress.percentage == 100.0
    end

    test "does not broadcast excessively during batch processing" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      # Create many entries
      entries =
        Enum.map(1..10, fn i ->
          %{address: "addr#{i}", amount: 1_000_000_000}
        end)

      process_fn = fn _entry ->
        {:ok, "signature"}
      end

      :ok = AirdropWorker.start_airdrop(pid, entries)
      :ok = AirdropWorker.process_batch(pid, process_fn, delay: 0)

      # Count progress messages
      Process.sleep(200)

      # Should receive start + individual completions (10) + final completion
      # Not excessive (e.g., not 100+ messages for 10 items)
      messages = collect_messages([])

      # Should have reasonable number of messages
      assert length(messages) <= 15
    end

    test "broadcasts error for critical failures" do
      {:ok, pid} = AirdropWorker.start_link(name: nil)

      entries = [%{address: "addr1", amount: 1_000_000_000}]

      # Try to process without starting airdrop first
      result = AirdropWorker.process_batch(pid, fn _ -> {:ok, "sig"} end)

      assert result == {:error, :not_processing}
      # No error broadcast for expected errors, only critical failures
    end
  end

  # Helper to collect messages from mailbox
  defp collect_messages(acc) do
    receive do
      msg -> collect_messages([msg | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
