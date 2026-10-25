defmodule TannhauserGateWeb.UserConfirmationInstructionsLive do
  use TannhauserGateWeb, :live_view

  on_mount {TannhauserGateWeb.UserAuth, :require_email_auth}

  alias TannhauserGate.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          {dgettext("player", "No confirmation instructions received?")}
          <:subtitle>
            {dgettext("player", "We'll send a new confirmation link to your inbox")}
          </:subtitle>
        </.header>

        <.form for={@form} id="resend_confirmation_form" phx-submit="send_instructions">
          <.input
            field={@form[:email]}
            type="email"
            label={dgettext("player", "Email")}
            placeholder={dgettext("player", "Email")}
            required
          />
          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button
              phx-disable-with={dgettext("player", "Sending...")}
              class="btn btn-primary console-action w-full"
            >
              {dgettext("player", "Resend confirmation instructions")}
            </.button>
          </div>
        </.form>

        <p class="text-center mt-4">
          <.link href={~p"/users/register"}>{dgettext("player", "Register")}</.link>
          | <.link href={~p"/users/log_in"}>{dgettext("player", "Log in")}</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    info =
      dgettext(
        "player",
        "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."
      )

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
