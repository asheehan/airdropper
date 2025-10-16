defmodule Airdropper.Repo do
  use Ecto.Repo,
    otp_app: :airdropper,
    adapter: Ecto.Adapters.Postgres
end
