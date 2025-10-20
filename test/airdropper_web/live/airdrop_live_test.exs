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
end
