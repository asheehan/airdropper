defmodule AirdropperWeb.AirdropLive do
  use AirdropperWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_files, [])
      |> assign(:processing, false)
      |> assign(:error_message, nil)
      |> allow_upload(:csv_file,
        accept: ~w(.csv),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true
      )

    {:ok, socket}
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
    uploaded_files =
      consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
        # For now, just store the file path
        # In the next phase, we'll process the CSV
        {:ok, path}
      end)

    socket =
      socket
      |> update(:uploaded_files, &(&1 ++ uploaded_files))
      |> put_flash(:info, "File uploaded successfully!")

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
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
                    <label for={@uploads.csv_file.ref} class="btn btn-primary btn-sm">
                      Choose File
                    </label>
                    <input
                      type="file"
                      id={@uploads.csv_file.ref}
                      class="hidden"
                      phx-hook="Phoenix.LiveView.Upload"
                      data-phx-upload-ref={@uploads.csv_file.ref}
                    />
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

          <%= if @uploaded_files != [] do %>
            <div class="mt-6">
              <h3 class="font-semibold mb-2">Uploaded Files:</h3>
              <ul class="list-disc list-inside">
                <%= for file <- @uploaded_files do %>
                  <li class="text-sm"><%= file %></li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>
      </div>

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
