defmodule Airdropper.CSVParserTest do
  use ExUnit.Case, async: true

  alias Airdropper.CSVParser

  @fixtures_dir Path.join([__DIR__, "..", "fixtures"])

  setup do
    File.mkdir_p!(@fixtures_dir)
    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)
    :ok
  end

  describe "parse_file/1 - valid files" do
    test "parses valid CSV with single entry" do
      file =
        create_csv_file("valid_single.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      assert entry.address == "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a"
      assert entry.amount == 1_500_000_000
    end

    test "parses valid CSV with multiple entries" do
      file =
        create_csv_file("valid_multiple.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,2.0
        9zMe1xKT5MsJ9B7nP4rS3yH8vW6gT9fN1nM7kJ5iH4c,0.5
        """)

      assert {:ok, entries} = CSVParser.parse_file(file)
      assert length(entries) == 3

      assert Enum.at(entries, 0).address == "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a"
      assert Enum.at(entries, 0).amount == 1_500_000_000

      assert Enum.at(entries, 1).address == "8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b"
      assert Enum.at(entries, 1).amount == 2_000_000_000

      assert Enum.at(entries, 2).address == "9zMe1xKT5MsJ9B7nP4rS3yH8vW6gT9fN1nM7kJ5iH4c"
      assert Enum.at(entries, 2).amount == 500_000_000
    end

    test "parses amounts with decimals correctly" do
      file =
        create_csv_file("decimals.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,0.123456789
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      # 0.123456789 SOL = 123,456,789 lamports
      assert entry.amount == 123_456_789
    end

    test "parses zero amount" do
      file =
        create_csv_file("zero.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,0
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      assert entry.amount == 0
    end

    test "trims whitespace from addresses and amounts" do
      file =
        create_csv_file("whitespace.csv", """
          7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a  ,  1.5
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      assert entry.address == "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a"
      assert entry.amount == 1_500_000_000
    end

    test "handles addresses at minimum valid length (32 chars)" do
      file =
        create_csv_file("min_address.csv", """
        11111111111111111111111111111111,1.0
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      assert entry.address == "11111111111111111111111111111111"
    end

    test "handles addresses at maximum valid length (44 chars)" do
      file =
        create_csv_file("max_address.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2aB,1.0
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      assert entry.address == "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2aB"
    end

    test "handles very large amounts" do
      file =
        create_csv_file("large_amount.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1000000.0
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      assert entry.amount == 1_000_000_000_000_000
    end
  end

  describe "parse_file/1 - invalid addresses" do
    test "rejects empty address" do
      file =
        create_csv_file("empty_address.csv", """
        ,1.5
        """)

      assert {:error, "Line 1: Empty wallet address"} = CSVParser.parse_file(file)
    end

    test "rejects address that is too short" do
      file =
        create_csv_file("short_address.csv", """
        shortaddr,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Line 1: Invalid wallet address 'shortaddr' (too short)"
    end

    test "rejects address that is too long" do
      file =
        create_csv_file("long_address.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2aB1TooLong,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Line 1: Invalid wallet address"
      assert error =~ "(too long)"
    end

    test "rejects address with invalid base58 characters" do
      file =
        create_csv_file("invalid_base58.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF20,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Line 1: Invalid wallet address"
      assert error =~ "(not valid base58)"
    end

    test "rejects address with lowercase 'l' (looks like 1)" do
      file =
        create_csv_file("invalid_l.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mKljH3gF2a,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "not valid base58"
    end

    test "rejects address with uppercase 'O' (looks like 0)" do
      file =
        create_csv_file("invalid_o.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2O,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "not valid base58"
    end

    test "rejects address with uppercase 'I' (looks like 1)" do
      file =
        create_csv_file("invalid_i.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2I,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "not valid base58"
    end
  end

  describe "parse_file/1 - invalid amounts" do
    test "rejects empty amount" do
      file =
        create_csv_file("empty_amount.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,
        """)

      assert {:error, "Line 1: Empty amount"} = CSVParser.parse_file(file)
    end

    test "rejects non-numeric amount" do
      file =
        create_csv_file("text_amount.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,notanumber
        """)

      assert {:error, "Line 1: Invalid amount 'notanumber' (not a number)"} =
               CSVParser.parse_file(file)
    end

    test "rejects negative amount" do
      file =
        create_csv_file("negative_amount.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,-1.5
        """)

      assert {:error, "Line 1: Negative amount '-1.5'"} = CSVParser.parse_file(file)
    end

    test "rejects amount with extra characters" do
      file =
        create_csv_file("extra_chars.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5SOL
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Line 1: Invalid amount '1.5SOL'"
      assert error =~ "(extra characters: 'SOL')"
    end
  end

  describe "parse_file/1 - invalid row structure" do
    test "rejects row with only one column" do
      file =
        create_csv_file("single_column.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a
        """)

      assert {:error, "Line 1: Missing amount column"} = CSVParser.parse_file(file)
    end

    test "rejects row with too many columns" do
      file =
        create_csv_file("too_many_columns.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5,extra
        """)

      assert {:error, "Line 1: Too many columns (expected 2, got 3)"} =
               CSVParser.parse_file(file)
    end

    test "rejects empty row" do
      file =
        create_csv_file("empty_row.csv", """

        """)

      assert {:error, "Line 1: Missing amount column"} = CSVParser.parse_file(file)
    end
  end

  describe "parse_file/1 - file errors" do
    test "returns error for non-existent file" do
      assert {:error, error} = CSVParser.parse_file("/non/existent/file.csv")
      assert error =~ "Failed to read file:"
    end

    test "returns error for directory instead of file" do
      assert {:error, error} = CSVParser.parse_file(@fixtures_dir)
      assert error =~ "Failed to read file:"
    end
  end

  describe "parse_file/1 - multi-line error reporting" do
    test "reports correct line number for error in middle of file" do
      file =
        create_csv_file("error_line_2.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        invalidaddress,2.0
        9zMe1xKT5MsJ9B7nP4rS3yH8vW6gT9fN1nM7kJ5iH4c,0.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Line 2:"
    end

    test "reports correct line number for error at end of file" do
      file =
        create_csv_file("error_line_3.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,2.0
        shortaddr,0.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Line 3:"
    end

    test "stops at first error and doesn't process remaining lines" do
      file =
        create_csv_file("stop_at_error.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        error,invalid
        9zMe1xKT5MsJ9B7nP4rS3yH8vW6gT9fN1nM7kJ5iH4c,0.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      # Should error on line 2, not process line 3
      assert error =~ "Line 2:"
    end
  end

  describe "parse_file/1 - edge cases" do
    test "handles CSV with quoted fields" do
      file =
        create_csv_file("quoted.csv", """
        "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a","1.5"
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      assert entry.address == "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a"
      assert entry.amount == 1_500_000_000
    end

    test "handles very small fractional amounts" do
      file =
        create_csv_file("tiny_amount.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,0.000000001
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      # 0.000000001 SOL = 1 lamport
      assert entry.amount == 1
    end

    test "rounds fractional lamports correctly" do
      file =
        create_csv_file("rounding.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,0.0000000015
        """)

      assert {:ok, [entry]} = CSVParser.parse_file(file)
      # 0.0000000015 SOL = 1.5 lamports, should round to 2
      assert entry.amount == 2
    end
  end

  describe "parse_file/1 - CSV header validation" do
    test "accepts CSV with valid headers" do
      file =
        create_csv_file("with_headers.csv", """
        address,amount
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,2.0
        """)

      assert {:ok, entries} = CSVParser.parse_file(file)
      assert length(entries) == 2
      # Should skip header row
      assert Enum.at(entries, 0).address == "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a"
    end

    test "accepts CSV with headers in different case" do
      file =
        create_csv_file("headers_case.csv", """
        Address,Amount
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        """)

      assert {:ok, entries} = CSVParser.parse_file(file)
      assert length(entries) == 1
    end

    test "accepts CSV with headers with extra whitespace" do
      file =
        create_csv_file("headers_whitespace.csv", """
          address  ,  amount
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        """)

      assert {:ok, entries} = CSVParser.parse_file(file)
      assert length(entries) == 1
    end

    test "rejects CSV with invalid header names" do
      file =
        create_csv_file("bad_headers.csv", """
        wallet,price
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Invalid CSV headers"
      assert error =~ "Expected: address,amount"
    end

    test "rejects CSV with only one header column" do
      file =
        create_csv_file("one_header.csv", """
        address
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Invalid CSV headers"
    end

    test "accepts CSV without headers (for backward compatibility)" do
      file =
        create_csv_file("no_headers.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,2.0
        """)

      assert {:ok, entries} = CSVParser.parse_file(file)
      assert length(entries) == 2
    end
  end

  describe "parse_file/1 - duplicate address detection" do
    test "rejects CSV with duplicate addresses" do
      file =
        create_csv_file("duplicates.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,2.0
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,3.0
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Duplicate wallet address"
      assert error =~ "7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a"
      assert error =~ "Line 3"
    end

    test "rejects CSV with multiple duplicates" do
      file =
        create_csv_file("multiple_duplicates.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,2.0
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,3.0
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,4.0
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      # Should fail on first duplicate encountered (line 3)
      assert error =~ "Duplicate wallet address"
      assert error =~ "Line 3"
    end

    test "accepts CSV with no duplicates" do
      file =
        create_csv_file("no_duplicates.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        8yKd9vJR3KqH8Z5mN2pQ1wF6tU4eR8dK9mJ5jH3gF2b,2.0
        9zMe1xKT5MsJ9B7nP4rS3yH8vW6gT9fN1nM7kJ5iH4c,3.0
        """)

      assert {:ok, entries} = CSVParser.parse_file(file)
      assert length(entries) == 3
    end

    test "duplicate detection is case-sensitive" do
      file =
        create_csv_file("case_sensitive.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
        7XKC9VJR3KQH8Z5MN2PQ1WF6TU4ER8DL9MK5JH3GF2A,2.0
        """)

      # These are different addresses (case matters), so should be accepted
      assert {:ok, entries} = CSVParser.parse_file(file)
      assert length(entries) == 2
    end

    test "detects duplicates after trimming whitespace" do
      file =
        create_csv_file("whitespace_duplicates.csv", """
        7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a,1.5
          7xKc9vJR3KqH8Z5mN2pQ1wF6tU4eR8dL9mK5jH3gF2a  ,2.0
        """)

      assert {:error, error} = CSVParser.parse_file(file)
      assert error =~ "Duplicate wallet address"
      assert error =~ "Line 2"
    end
  end

  # Helper function to create temporary CSV files for testing
  defp create_csv_file(filename, content) do
    path = Path.join(@fixtures_dir, filename)
    File.write!(path, content)
    path
  end
end
