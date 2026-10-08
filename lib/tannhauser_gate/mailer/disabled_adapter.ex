defmodule TannhauserGate.Mailer.DisabledAdapter do
  @moduledoc """
  Rejects delivery until a production email provider is configured.
  """
  use Swoosh.Adapter

  require Logger

  @impl true
  def deliver(_email, _config) do
    Logger.warning("Email delivery unavailable: no production mail provider configured")
    {:error, :email_delivery_not_configured}
  end
end
