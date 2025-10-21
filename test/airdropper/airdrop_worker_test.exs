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
end
