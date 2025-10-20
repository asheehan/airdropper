defmodule Airdropper.CSVParser do
  @moduledoc """
  Parses CSV files containing airdrop data (wallet addresses and amounts).
  """

  NimbleCSV.define(AirdropParser, separator: ",", escape: "\"")

  @type parsed_entry :: %{address: String.t(), amount: non_neg_integer()}
  @type parse_result :: {:ok, [parsed_entry()]} | {:error, String.t()}

  @doc """
  Parses a CSV file and returns a list of airdrop entries.

  Expected CSV format:
  - First column: Solana wallet address (base58 string, typically 32-44 characters)
  - Second column: Amount in SOL (decimal number)

  Returns parsed data with amounts converted to lamports (1 SOL = 1_000_000_000 lamports).

  ## Examples

      iex> parse_file("/path/to/file.csv")
      {:ok, [%{address: "7xswpE...", amount: 1_500_000_000}]}

      iex> parse_file("/path/to/invalid.csv")
      {:error, "Invalid amount on line 2: not_a_number"}
  """
  @spec parse_file(String.t()) :: parse_result()
  def parse_file(file_path) do
    file_path
    |> File.stream!()
    |> AirdropParser.parse_stream(skip_headers: false)
    |> Enum.to_list()
    |> process_rows()
  rescue
    e in File.Error ->
      {:error, "Failed to read file: #{e.reason}"}

    e ->
      {:error, "Unexpected error: #{Exception.message(e)}"}
  end

  # Process all rows, detecting and skipping headers if present
  defp process_rows([first_row | rest_rows]) do
    case detect_header(first_row) do
      :has_header ->
        # Skip header row and process the rest
        parse_rows(rest_rows, 2)

      :no_header ->
        # Process all rows including the first one
        parse_rows([first_row | rest_rows], 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_rows([]) do
    {:ok, []}
  end

  # Detect if first row is a header row
  defp detect_header([col1, col2]) do
    normalized_col1 = String.trim(col1) |> String.downcase()
    normalized_col2 = String.trim(col2) |> String.downcase()

    cond do
      normalized_col1 == "address" and normalized_col2 == "amount" ->
        :has_header

      # If first column looks like a header but doesn't match expected format
      normalized_col1 in ["wallet", "address", "public_key", "pubkey"] and
          normalized_col2 not in ["amount"] ->
        {:error, "Invalid CSV headers. Expected: address,amount"}

      # Otherwise assume no header (data row)
      true ->
        :no_header
    end
  end

  defp detect_header([single_col]) do
    # Could be a header with only one column - check if it's the word "address"
    normalized = String.trim(single_col) |> String.downcase()

    if normalized in ["address", "wallet", "public_key", "pubkey"] do
      {:error, "Invalid CSV headers. Expected: address,amount"}
    else
      :no_header
    end
  end

  defp detect_header(_other) do
    :no_header
  end

  # Parse rows with duplicate detection
  defp parse_rows(rows, starting_line) do
    rows
    |> Enum.with_index(starting_line)
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {row, line_num},
                                                     {:ok, acc, seen_addresses} ->
      case parse_row(row, line_num) do
        {:ok, entry} ->
          if MapSet.member?(seen_addresses, entry.address) do
            {:halt, {:error, "Line #{line_num}: Duplicate wallet address '#{entry.address}'"}}
          else
            {:cont, {:ok, [entry | acc], MapSet.put(seen_addresses, entry.address)}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries, _seen} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Parses a single CSV row into an airdrop entry.
  @spec parse_row([String.t()], integer()) :: {:ok, parsed_entry()} | {:error, String.t()}
  defp parse_row([address, amount_str], line_num) do
    with {:ok, address} <- validate_address(address, line_num),
         {:ok, amount} <- parse_amount(amount_str, line_num) do
      {:ok, %{address: address, amount: amount}}
    end
  end

  defp parse_row([_single_value], line_num) do
    {:error, "Line #{line_num}: Missing amount column"}
  end

  defp parse_row(row, line_num) when length(row) > 2 do
    {:error, "Line #{line_num}: Too many columns (expected 2, got #{length(row)})"}
  end

  defp parse_row([], line_num) do
    {:error, "Line #{line_num}: Empty row"}
  end

  # Validates a Solana wallet address.
  @spec validate_address(String.t(), integer()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_address(address, line_num) do
    trimmed = String.trim(address)

    cond do
      trimmed == "" ->
        {:error, "Line #{line_num}: Empty wallet address"}

      String.length(trimmed) < 32 ->
        {:error, "Line #{line_num}: Invalid wallet address '#{trimmed}' (too short)"}

      String.length(trimmed) > 44 ->
        {:error, "Line #{line_num}: Invalid wallet address '#{trimmed}' (too long)"}

      !valid_base58?(trimmed) ->
        {:error, "Line #{line_num}: Invalid wallet address '#{trimmed}' (not valid base58)"}

      true ->
        {:ok, trimmed}
    end
  end

  # Parses an amount string and converts it to lamports.
  # 1 SOL = 1_000_000_000 lamports
  @spec parse_amount(String.t(), integer()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  defp parse_amount(amount_str, line_num) do
    trimmed = String.trim(amount_str)

    cond do
      trimmed == "" ->
        {:error, "Line #{line_num}: Empty amount"}

      true ->
        case Float.parse(trimmed) do
          {amount_float, ""} when amount_float >= 0 ->
            # Convert SOL to lamports (1 SOL = 1_000_000_000 lamports)
            lamports = round(amount_float * 1_000_000_000)
            {:ok, lamports}

          {_amount_float, ""} ->
            {:error, "Line #{line_num}: Negative amount '#{trimmed}'"}

          {_amount_float, remainder} ->
            {:error,
             "Line #{line_num}: Invalid amount '#{trimmed}' (extra characters: '#{remainder}')"}

          :error ->
            {:error, "Line #{line_num}: Invalid amount '#{trimmed}' (not a number)"}
        end
    end
  end

  # Checks if a string is valid base58.
  # Base58 alphabet: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
  # (excludes 0, O, I, l to avoid confusion)
  @spec valid_base58?(String.t()) :: boolean()
  defp valid_base58?(str) do
    String.match?(str, ~r/^[1-9A-HJ-NP-Za-km-z]+$/)
  end
end
