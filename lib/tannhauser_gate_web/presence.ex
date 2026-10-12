defmodule TannhauserGateWeb.Presence do
  @moduledoc """
  Who is online in each GDR (see `TannhauserGateWeb.GdrPresence`).
  """
  use Phoenix.Presence,
    otp_app: :tannhauser_gate,
    pubsub_server: TannhauserGate.PubSub
end
