defmodule AirdropperWeb.AirdropLive do
  use AirdropperWeb, :live_view

  alias Airdropper.CSVParser

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to airdrop progress updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Airdropper.PubSub, "airdrop:progress")
    end

    socket =
      socket
      |> assign(:parsed_entries, [])
      |> assign(:processing, false)
      |> assign(:error_message, nil)
      |> assign(:airdrop_status, :idle)
      |> assign(:progress, %{total: 0, completed: 0, failed: 0, percentage: 0.0})
      |> assign(:recent_transfers, [])
      |> allow_upload(:csv_file,
        accept: ~w(.csv),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:airdrop_started, %{total: total}}, socket) do
    socket =
      socket
      |> assign(:airdrop_status, :processing)
      |> assign(:progress, %{total: total, completed: 0, failed: 0, percentage: 0.0})
      |> assign(:recent_transfers, [])
      |> put_flash(:info, "Airdrop started! Processing #{total} transfers...")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:transfer_completed, result}, socket) do
    # Add to recent transfers (keep last 10)
    recent_transfers = [result | socket.assigns.recent_transfers] |> Enum.take(10)

    {:noreply, assign(socket, :recent_transfers, recent_transfers)}
  end

  @impl true
  def handle_info({:airdrop_progress, progress}, socket) do
    {:noreply, assign(socket, :progress, progress)}
  end

  @impl true
  def handle_info({:airdrop_completed, final_state}, socket) do
    socket =
      socket
      |> assign(:airdrop_status, final_state.status)
      |> assign(:progress, final_state.progress)
      |> assign(:processing, false)
      |> put_flash(
        :info,
        "Airdrop completed! #{final_state.progress.completed} successful, #{final_state.progress.failed} failed"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_airdrop", _params, socket) do
    # Start the airdrop using the AirdropWorker
    entries = socket.assigns.parsed_entries

    case Airdropper.AirdropWorker.start_airdrop(Airdropper.AirdropWorker, entries) do
      :ok ->
        # Start processing with the mock transfer function
        process_fn = fn entry ->
          Airdropper.SolanaTransfer.execute_transfer(entry)
        end

        Airdropper.AirdropWorker.process_batch(Airdropper.AirdropWorker, process_fn)

        socket =
          socket
          |> assign(:processing, true)
          |> put_flash(:info, "Starting airdrop...")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start airdrop: #{reason}")}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_file, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    socket =
      consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
        case CSVParser.parse_file(path) do
          {:ok, entries} ->
            {:ok, entries}

          {:error, reason} ->
            {:postpone, reason}
        end
      end)
      |> case do
        [] ->
          socket
          |> put_flash(:error, "No file was uploaded")

        [entries] when is_list(entries) ->
          socket
          |> assign(:parsed_entries, entries)
          |> assign(:error_message, nil)
          |> put_flash(:info, "Successfully parsed #{length(entries)} airdrop entries!")

        [error_reason] when is_binary(error_reason) ->
          socket
          |> assign(:error_message, error_reason)
          |> put_flash(:error, error_reason)
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash kind={:info} flash={@flash} />
    <.flash kind={:error} flash={@flash} />
    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-base-content">
          Solana Airdrop Manager
        </h1>
        <p class="mt-2 text-base-content/70">
          Upload a CSV file with wallet addresses and amounts to process airdrops on Solana devnet
        </p>
      </div>

      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title">Upload CSV File</h2>

          <form phx-submit="save" phx-change="validate" class="mt-4">
            <div class="form-control w-full">
              <label class="label">
                <span class="label-text">Select CSV file (max 10MB)</span>
              </label>

              <div
                class="border-2 border-dashed border-base-300 rounded-lg p-8 text-center hover:border-primary transition-colors"
                phx-drop-target={@uploads.csv_file.ref}
              >
                <div class="flex flex-col items-center justify-center gap-2">
                  <svg
                    class="w-12 h-12 text-base-content/40"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
                    />
                  </svg>
                  <div>
                    <label class="btn btn-primary btn-sm cursor-pointer">
                      <.live_file_input upload={@uploads.csv_file} class="hidden" />
                      Choose File
                    </label>
                    <p class="text-sm text-base-content/60 mt-2">
                      or drag and drop
                    </p>
                  </div>
                  <p class="text-xs text-base-content/50">
                    CSV files only, up to 10MB
                  </p>
                </div>
              </div>

              <%= for entry <- @uploads.csv_file.entries do %>
                <div class="mt-4 p-4 bg-base-200 rounded-lg">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-3">
                      <svg class="w-8 h-8 text-success" fill="currentColor" viewBox="0 0 20 20">
                        <path
                          fill-rule="evenodd"
                          d="M4 4a2 2 0 012-2h4.586A2 2 0 0112 2.586L15.414 6A2 2 0 0116 7.414V16a2 2 0 01-2 2H6a2 2 0 01-2-2V4z"
                          clip-rule="evenodd"
                        />
                      </svg>
                      <div>
                        <p class="font-medium"><%= entry.client_name %></p>
                        <p class="text-sm text-base-content/60">
                          <%= Float.round(entry.client_size / 1_000_000, 2) %> MB
                        </p>
                      </div>
                    </div>
                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      class="btn btn-ghost btn-sm btn-circle"
                      aria-label="cancel"
                    >
                      ✕
                    </button>
                  </div>

                  <progress
                    class="progress progress-primary w-full mt-2"
                    value={entry.progress}
                    max="100"
                  >
                    <%= entry.progress %>%
                  </progress>
                </div>

                <%= for err <- upload_errors(@uploads.csv_file, entry) do %>
                  <div class="alert alert-error mt-2">
                    <span><%= error_to_string(err) %></span>
                  </div>
                <% end %>
              <% end %>

              <%= for err <- upload_errors(@uploads.csv_file) do %>
                <div class="alert alert-error mt-2">
                  <span><%= error_to_string(err) %></span>
                </div>
              <% end %>
            </div>

            <div class="card-actions justify-end mt-6">
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@uploads.csv_file.entries == []}
              >
                Upload and Process
              </button>
            </div>
          </form>

          <%= if @parsed_entries != [] do %>
            <div class="mt-6">
              <h3 class="font-semibold mb-3">Parsed Airdrop Entries (<%= length(@parsed_entries) %> total):</h3>
              <div class="overflow-x-auto">
                <table class="table table-zebra table-sm">
                  <thead>
                    <tr>
                      <th>#</th>
                      <th>Wallet Address</th>
                      <th class="text-right">Amount (SOL)</th>
                      <th class="text-right">Amount (Lamports)</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for {entry, idx} <- Enum.with_index(@parsed_entries, 1) do %>
                      <tr>
                        <td><%= idx %></td>
                        <td class="font-mono text-xs"><%= entry.address %></td>
                        <td class="text-right"><%= entry.amount / 1_000_000_000 %></td>
                        <td class="text-right font-mono text-xs"><%= entry.amount %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
              <div class="mt-4 stats shadow">
                <div class="stat">
                  <div class="stat-title">Total Entries</div>
                  <div class="stat-value text-2xl"><%= length(@parsed_entries) %></div>
                </div>
                <div class="stat">
                  <div class="stat-title">Total Amount</div>
                  <div class="stat-value text-2xl">
                    <%= Enum.sum(Enum.map(@parsed_entries, & &1.amount)) / 1_000_000_000 %> SOL
                  </div>
                </div>
              </div>

              <!-- Start Airdrop Button -->
              <div class="mt-6 card-actions justify-end">
                <button
                  phx-click="start_airdrop"
                  class="btn btn-success btn-lg"
                  disabled={@processing or @airdrop_status == :processing}
                >
                  <%= if @processing do %>
                    <span class="loading loading-spinner"></span>
                    Processing...
                  <% else %>
                    🚀 Start Airdrop
                  <% end %>
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Progress Dashboard -->
      <%= if @airdrop_status != :idle or @progress.total > 0 do %>
        <div class="mt-8 card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Airdrop Progress</h2>

            <!-- Progress Bar -->
            <div class="mt-4">
              <div class="flex justify-between items-center mb-2">
                <span class="text-sm font-medium">Overall Progress</span>
                <span class="text-sm font-bold"><%= @progress.percentage %>%</span>
              </div>
              <progress
                class="progress progress-primary w-full h-4"
                value={@progress.percentage}
                max="100"
              >
              </progress>
            </div>

            <!-- Stats Grid -->
            <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
              <!-- Processed Card -->
              <div class="stat bg-primary/10 rounded-lg">
                <div class="stat-figure text-primary">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"></path>
                  </svg>
                </div>
                <div class="stat-title text-primary">Processed</div>
                <div class="stat-value text-primary text-3xl"><%= @progress.completed + @progress.failed %></div>
                <div class="stat-desc">of <%= @progress.total %> total</div>
              </div>

              <!-- Successful Card -->
              <div class="stat bg-success/10 rounded-lg">
                <div class="stat-figure text-success">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                  </svg>
                </div>
                <div class="stat-title text-success">Successful</div>
                <div class="stat-value text-success text-3xl"><%= @progress.completed %></div>
                <div class="stat-desc"><%= if @progress.total > 0, do: Float.round(@progress.completed / @progress.total * 100, 1), else: 0 %>% success rate</div>
              </div>

              <!-- Failed Card -->
              <div class="stat bg-error/10 rounded-lg">
                <div class="stat-figure text-error">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                  </svg>
                </div>
                <div class="stat-title text-error">Failed</div>
                <div class="stat-value text-error text-3xl"><%= @progress.failed %></div>
                <div class="stat-desc"><%= if @progress.total > 0, do: Float.round(@progress.failed / @progress.total * 100, 1), else: 0 %>% failure rate</div>
              </div>
            </div>

            <!-- Recent Transfers -->
            <%= if @recent_transfers != [] do %>
              <div class="mt-6">
                <h3 class="font-semibold mb-3">Recent Transfers</h3>
                <div class="overflow-x-auto">
                  <table class="table table-sm">
                    <thead>
                      <tr>
                        <th>Address</th>
                        <th>Status</th>
                        <th>Signature / Error</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for transfer <- @recent_transfers do %>
                        <tr>
                          <td class="font-mono text-xs"><%= String.slice(transfer.address, 0..10) %>...</td>
                          <td>
                            <%= if transfer.status == :success do %>
                              <span class="badge badge-success badge-sm">Success</span>
                            <% else %>
                              <span class="badge badge-error badge-sm">Failed</span>
                            <% end %>
                          </td>
                          <td class="font-mono text-xs">
                            <%= if transfer.signature do %>
                              <%= String.slice(transfer.signature, 0..10) %>...
                            <% else %>
                              <%= transfer.error %>
                            <% end %>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>

            <!-- Status Badge -->
            <div class="mt-4 flex justify-center">
              <%= case @airdrop_status do %>
                <% :processing -> %>
                  <div class="badge badge-primary badge-lg gap-2">
                    <span class="loading loading-spinner loading-xs"></span>
                    Processing
                  </div>
                <% :completed -> %>
                  <div class="badge badge-success badge-lg">
                    ✓ Completed
                  </div>
                <% :failed -> %>
                  <div class="badge badge-error badge-lg">
                    ✗ Failed
                  </div>
                <% _ -> %>
                  <div class="badge badge-ghost badge-lg">Idle</div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <div class="mt-8 p-6 bg-base-200 rounded-lg">
        <h3 class="font-semibold mb-3">CSV Format Requirements:</h3>
        <ul class="list-disc list-inside space-y-2 text-sm text-base-content/70">
          <li>First column: Wallet address (Solana public key)</li>
          <li>Second column: Amount (in SOL)</li>
          <li>No header row required</li>
          <li>Example: <code class="bg-base-300 px-2 py-1 rounded">7xswpE...,1.5</code></li>
        </ul>
      </div>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:not_accepted), do: "File type not accepted (CSV only)"
  defp error_to_string(:too_many_files), do: "Too many files (max 1)"
  defp error_to_string(err), do: "Upload error: #{inspect(err)}"
end
