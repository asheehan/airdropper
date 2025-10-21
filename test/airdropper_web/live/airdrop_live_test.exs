defmodule AirdropperWeb.AirdropLiveTest do
  use AirdropperWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "AirdropLive - mount and rendering" do
    test "disconnected and connected mount", %{conn: conn} do
      {:ok, page_live, disconnected_html} = live(conn, ~p"/airdrop")
      assert disconnected_html =~ "Solana Airdrop Manager"
      assert render(page_live) =~ "Upload CSV File"
    end

    test "displays file upload area", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      assert render(view) =~ "Choose File"
      assert render(view) =~ "or drag and drop"
      assert render(view) =~ "CSV files only, up to 10MB"
    end

    test "displays CSV format requirements", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      assert render(view) =~ "CSV Format Requirements"
      assert render(view) =~ "Wallet address"
      assert render(view) =~ "Amount (in SOL)"
    end

    test "upload button is disabled when no file selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")
      assert render(view) =~ "disabled"
    end

    test "does not display parsed entries on initial load", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")
      refute html =~ "Parsed Airdrop Entries"
      refute html =~ "Total Entries"
    end
  end

  describe "AirdropLive - activity log" do
    setup do
      Phoenix.PubSub.subscribe(Airdropper.PubSub, "airdrop:progress")
      :ok
    end

    test "displays activity log when transfers are completed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      # Simulate a successful transfer completion
      send(
        view.pid,
        {:transfer_completed,
         %{
           address: "7xswpEPCV6gKuryRaJWrinspLHj48o5kvhzHdNS2pump",
           signature: "5J7ZqWZuV2kFJDh3RGnpxVyH4v1dQz2YqWXgB7H2pump",
           status: :success,
           error: nil,
           timestamp: DateTime.utc_now()
         }}
      )

      html = render(view)
      assert html =~ "Activity Log"
      assert html =~ "7xswpEPCV6gKury"
      assert html =~ "5J7ZqWZuV2kFJD"
      assert html =~ "✓"
    end

    test "displays failed transfers with error icon", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      # Simulate a failed transfer
      send(
        view.pid,
        {:transfer_completed,
         %{
           address: "7xswpEPCV6gKuryRaJWrispLHj48o5kvhzHdNS2pump",
           signature: nil,
           status: :failed,
           error: "Insufficient funds",
           timestamp: DateTime.utc_now()
         }}
      )

      html = render(view)
      assert html =~ "Activity Log"
      assert html =~ "7xswpEPCV6gKury"
      assert html =~ "✗"
      assert html =~ "Insufficient funds"
    end

    test "limits activity log to last 100 transfers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      # Send 150 transfer completions
      for i <- 1..150 do
        send(
          view.pid,
          {:transfer_completed,
           %{
             address: "address_#{i}",
             signature: "signature_#{i}",
             status: :success,
             error: nil,
             timestamp: DateTime.utc_now()
           }}
        )
      end

      # Check that activity_log has exactly 100 entries
      state = :sys.get_state(view.pid)
      activity_log = state.socket.assigns.activity_log
      assert length(activity_log) == 100

      # Verify the most recent entries are kept
      assert List.first(activity_log).address == "address_150"
      assert List.last(activity_log).address == "address_51"
    end

    test "activity log displays timestamp for each transfer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      timestamp = DateTime.utc_now()

      send(
        view.pid,
        {:transfer_completed,
         %{
           address: "7xswpEPCV6gKuryRaJWrispLHj48o5kvhzHdNS2pump",
           signature: "5J7ZqWZuV2kFJDh3RGnpxVyH4v1dQz2YqWXgB7H2pump",
           status: :success,
           error: nil,
           timestamp: timestamp
         }}
      )

      html = render(view)
      # Check for time display (HH:MM:SS format)
      assert html =~ ~r/\d{2}:\d{2}:\d{2}/
    end

    test "activity log shows truncated addresses", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      full_address = "7xswpEPCV6gKuryRaJWrispLHj48o5kvhzHdNS2pump"

      send(
        view.pid,
        {:transfer_completed,
         %{
           address: full_address,
           signature: "sig123",
           status: :success,
           error: nil,
           timestamp: DateTime.utc_now()
         }}
      )

      html = render(view)
      # Should show truncated version (first 15 chars + ...)
      assert html =~ "7xswpEPCV6gKury"
      # Should not show the full address in the activity log
      refute html =~ full_address
    end

    test "expandable details for failed transfers shows full error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      send(
        view.pid,
        {:transfer_completed,
         %{
           address: "7xswpEPCV6gKuryRaJWrispLHj48o5kvhzHdNS2pump",
           signature: nil,
           status: :failed,
           error: "Transaction simulation failed: Insufficient funds for rent",
           timestamp: DateTime.utc_now()
         }}
      )

      html = render(view)
      # Error should be visible (we'll use a collapse/details component)
      assert html =~ "Transaction simulation failed"
    end

    test "activity log has scrollable container with id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/airdrop")

      send(
        view.pid,
        {:transfer_completed,
         %{
           address: "addr1",
           signature: "sig1",
           status: :success,
           error: nil,
           timestamp: DateTime.utc_now()
         }}
      )

      html = render(view)
      # Check for activity-log container with overflow-y-auto class
      assert html =~ ~r/id="activity-log"/
      assert html =~ ~r/overflow-y-auto/
    end

    test "activity log does not display when empty", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/airdrop")

      # Activity log section should not render when there are no transfers
      refute html =~ "Activity Log"
    end
  end
end
