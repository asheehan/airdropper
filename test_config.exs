#!/usr/bin/env elixir

IO.puts("Testing Solana configuration...")
IO.puts("")

# Test 1: Check application config
IO.puts("1. Application Config:")
config = Application.get_env(:airdropper, :solana)
IO.inspect(config, label: "Solana config")
IO.puts("")

# Test 2: Load the keypair
IO.puts("2. Loading Keypair:")
keypair_path = config[:authority_private_key]

if keypair_path do
  case Solana.Key.pair_from_file(keypair_path) do
    {:ok, keypair} ->
      pubkey = Solana.pubkey!(keypair)
      IO.puts("✓ Keypair loaded successfully")
      IO.inspect(B58.encode58(pubkey), label: "Public Key (Base58)")

    {:error, reason} ->
      IO.puts("✗ Failed to load keypair")
      IO.inspect(reason)
  end
else
  IO.puts("✗ No keypair path configured")
end

IO.puts("")

# Test 3: Test RPC connection
IO.puts("3. Testing RPC Connection:")
rpc_url = config[:rpc_url]
IO.puts("Using RPC URL: #{String.replace(rpc_url, ~r/api-key=[^&]+/, "api-key=***")}")

client = Solana.RPC.client(network: rpc_url)

# Get the balance of our wallet to test the connection
case Solana.Key.pair_from_file(keypair_path) do
  {:ok, keypair} ->
    pubkey = Solana.pubkey!(keypair)

    case Solana.RPC.send(client, Solana.RPC.Request.get_balance(pubkey)) do
      {:ok, balance} ->
        IO.puts("✓ RPC connection successful")
        IO.inspect(balance, label: "Wallet Balance (lamports)")
        IO.puts("Balance: #{balance / 1_000_000_000} SOL")

      {:error, reason} ->
        IO.puts("✗ RPC connection failed")
        IO.inspect(reason)
    end

  _ ->
    IO.puts("✗ Could not load keypair for balance check")
end

IO.puts("")
IO.puts("Configuration test complete!")
