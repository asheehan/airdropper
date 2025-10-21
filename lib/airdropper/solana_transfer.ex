defmodule Airdropper.SolanaTransfer do
  @moduledoc """
  Mock Solana transfer functionality for testing airdrop operations.

  This module simulates blockchain transfers with realistic timing and
  success/failure rates without requiring actual Solana connection.
  """

  @doc """
  Executes a mock SOL transfer to the given address.

  ## Parameters
  - `entry` - A map containing:
    - `:address` - The recipient's Solana wallet address (required)
    - `:amount` - The amount to transfer in lamports (required)
  - `opts` - Optional keyword list:
    - `:delay` - Custom delay in milliseconds (default: random 1000-3000ms)

  ## Returns
  - `{:ok, signature}` - Success with a mock transaction signature (88 char base58 string)
  - `{:error, reason}` - Failure with an error message

  ## Behavior
  - Takes 1-3 seconds to simulate network latency (configurable)
  - 80% success rate, 20% failure rate
  - Each successful transfer gets a unique transaction signature

  ## Examples

      iex> Airdropper.SolanaTransfer.execute_transfer(%{address: "abc...", amount: 1_000_000_000})
      {:ok, "5VqB..."}

      iex> Airdropper.SolanaTransfer.execute_transfer(%{address: "abc...", amount: 1_000_000_000}, delay: 0)
      {:error, "Insufficient funds"}
  """
  @spec execute_transfer(%{address: String.t(), amount: non_neg_integer()}, keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def execute_transfer(entry, opts \\ [])

  def execute_transfer(entry, opts) when is_map(entry) do
    # Access fields to raise KeyError if missing
    address = Map.fetch!(entry, :address)
    amount = Map.fetch!(entry, :amount)

    # Simulate network latency (1-3 seconds by default, configurable for tests)
    delay = Keyword.get(opts, :delay, Enum.random(1000..3000))
    if delay > 0, do: Process.sleep(delay)

    # 80% success rate
    if :rand.uniform() <= 0.8 do
      {:ok, generate_signature(address, amount)}
    else
      {:error, random_error_message()}
    end
  end

  # Private Functions

  # Generates a unique-looking mock Solana transaction signature
  # Solana signatures are 88 characters in base58 encoding
  defp generate_signature(address, amount) do
    # Create a pseudo-unique string based on address, amount, and current time
    unique_input = "#{address}#{amount}#{System.system_time(:nanosecond)}#{:rand.uniform()}"

    # Hash it to get deterministic randomness
    hash = :crypto.hash(:sha256, unique_input)

    # Convert to base58 (Solana uses base58 for signatures)
    # Base58 alphabet: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
    base58_chars = ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    # Generate 88 characters
    hash
    |> :binary.bin_to_list()
    |> Stream.cycle()
    |> Stream.take(88)
    |> Enum.map(fn byte ->
      Enum.at(base58_chars, rem(byte, length(base58_chars)))
    end)
    |> List.to_string()
  end

  # Returns a random error message to simulate various blockchain failures
  defp random_error_message do
    errors = [
      "Insufficient funds",
      "Network timeout",
      "Transaction simulation failed",
      "Blockhash not found",
      "Account not found",
      "Invalid account data",
      "Transaction expired",
      "Node is behind",
      "RPC request failed",
      "Slippage tolerance exceeded"
    ]

    Enum.random(errors)
  end
end
