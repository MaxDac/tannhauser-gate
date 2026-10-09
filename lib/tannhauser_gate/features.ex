defmodule TannhauserGate.Features do
  @moduledoc """
  Runtime feature flags.

  `email_auth?/0` is controlled by the `FEATURE_EMAIL_AUTH` env var (`true`
  or `1` enables it, see `config/runtime.exs`). While disabled, no email is
  sent, emails are never verified and users log in with their username.
  """

  @doc "Whether the email delivery and verification flows are enabled."
  def email_auth?, do: Application.get_env(:tannhauser_gate, :feature_email_auth, false)
end
