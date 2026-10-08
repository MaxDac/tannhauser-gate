defmodule TannhauserGate.Repo do
  use Ecto.Repo,
    otp_app: :tannhauser_gate,
    adapter: Ecto.Adapters.Postgres
end
