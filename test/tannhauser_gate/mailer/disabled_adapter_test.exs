defmodule TannhauserGate.Mailer.DisabledAdapterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Swoosh.Email

  alias TannhauserGate.Mailer.DisabledAdapter

  test "delivery fails explicitly without logging recipients or confirmation links" do
    email =
      new()
      |> to("private-recipient@example.com")
      |> text_body("https://example.com/users/confirm/private-confirmation-link")

    log =
      capture_log(fn ->
        assert DisabledAdapter.deliver(email, []) == {:error, :email_delivery_not_configured}
      end)

    assert log =~ "no production mail provider configured"
    refute log =~ "private-recipient"
    refute log =~ "private-confirmation-link"
  end
end
