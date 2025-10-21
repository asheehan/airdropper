defmodule Airdropper.SolanaTransferTest do
  use ExUnit.Case, async: true

  alias Airdropper.SolanaTransfer

  describe "execute_transfer/1" do
    test "returns success with signature for valid entry" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 1_000_000_000}

      result = SolanaTransfer.execute_transfer(entry)

      assert {:ok, signature} = result
      assert is_binary(signature)
      assert String.length(signature) > 0
    end

    test "signature is a valid base58 string" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 1_000_000_000}

      {:ok, signature} = SolanaTransfer.execute_transfer(entry)

      # Base58 uses characters: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
      # Should not contain: 0, O, I, l
      refute String.contains?(signature, ["0", "O", "I", "l"])
      assert signature =~ ~r/^[1-9A-HJ-NP-Za-km-z]+$/
    end

    test "signature length is typical for Solana transactions (88 chars)" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 1_000_000_000}

      {:ok, signature} = SolanaTransfer.execute_transfer(entry)

      # Solana transaction signatures are typically 88 characters in base58
      assert String.length(signature) == 88
    end

    test "takes realistic time (1-3 seconds)" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 1_000_000_000}

      start_time = System.monotonic_time(:millisecond)
      SolanaTransfer.execute_transfer(entry)
      elapsed = System.monotonic_time(:millisecond) - start_time

      # Should take between 1000ms and 3000ms
      assert elapsed >= 1000
      # Allow small buffer for execution overhead
      assert elapsed <= 3100
    end

    test "sometimes returns error (failure rate around 20%)" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 1_000_000_000}

      # Run 100 transfers and check failure rate (use delay: 0 for fast tests)
      results =
        Enum.map(1..100, fn _ ->
          SolanaTransfer.execute_transfer(entry, delay: 0)
        end)

      failures = Enum.count(results, fn result -> match?({:error, _}, result) end)
      successes = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      # Should have some failures (roughly 20%)
      # We'll be lenient: between 10% and 35% to account for randomness
      assert failures >= 10
      assert failures <= 35
      assert successes >= 65
      assert successes <= 90
      assert failures + successes == 100
    end

    test "error returns descriptive message" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 1_000_000_000}

      # Keep trying until we get an error (should happen within 20 attempts on average)
      # Use delay: 0 for fast tests
      result =
        Enum.find_value(1..50, fn _ ->
          case SolanaTransfer.execute_transfer(entry, delay: 0) do
            {:error, _} = error -> error
            {:ok, _} -> nil
          end
        end)

      assert {:error, reason} = result
      assert is_binary(reason)
      assert String.length(reason) > 0
    end

    test "different entries produce different signatures" do
      entry1 = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 1_000_000_000}
      entry2 = %{address: "8yLd1wKS4rLp9aY6nX3tZ7vW2fU5eT9cM1nJ8kH4bQ3", amount: 2_000_000_000}

      # Get successful results (retry if we hit the 20% failure rate, use delay: 0 for speed)
      sig1 =
        Enum.find_value(1..10, fn _ ->
          case SolanaTransfer.execute_transfer(entry1, delay: 0) do
            {:ok, sig} -> sig
            {:error, _} -> nil
          end
        end)

      sig2 =
        Enum.find_value(1..10, fn _ ->
          case SolanaTransfer.execute_transfer(entry2, delay: 0) do
            {:ok, sig} -> sig
            {:error, _} -> nil
          end
        end)

      assert sig1 != sig2
    end

    test "handles missing address field" do
      entry = %{amount: 1_000_000_000}

      assert_raise KeyError, fn ->
        SolanaTransfer.execute_transfer(entry)
      end
    end

    test "handles missing amount field" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a"}

      assert_raise KeyError, fn ->
        SolanaTransfer.execute_transfer(entry)
      end
    end

    test "accepts zero amount" do
      entry = %{address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a", amount: 0}

      # Should not crash, should return either success or error
      result = SolanaTransfer.execute_transfer(entry)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts large amounts" do
      entry = %{
        address: "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a",
        amount: 1_000_000_000_000_000
      }

      # Should not crash, should return either success or error
      result = SolanaTransfer.execute_transfer(entry)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
