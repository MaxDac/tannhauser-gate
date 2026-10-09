defmodule TannhauserGateWeb.UserLoginLive do
  use TannhauserGateWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="mx-auto max-w-sm">
        <.header class="text-center">
          Log in
          <:subtitle>
            Don't have an account?
            <.link navigate={~p"/users/register"} class="font-semibold text-mint hover:underline">
              Register
            </.link>
            for an account now.
          </:subtitle>
        </.header>

        <.form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
          <.input
            field={@form[:login]}
            type="text"
            label={if(@email_auth?, do: "Username or email", else: "Username")}
            autocomplete="username"
            required
          />
          <.input field={@form[:password]} type="password" label="Password" required />

          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
            <.link
              :if={@email_auth?}
              href={~p"/users/reset_password"}
              class="text-sm font-semibold"
            >
              Forgot your password?
            </.link>
          </div>
          <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
            <.button phx-disable-with="Logging in..." class="btn btn-primary console-action w-full">
              Log in <span aria-hidden="true">→</span>
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    login = Phoenix.Flash.get(socket.assigns.flash, :login)
    form = to_form(%{"login" => login}, as: "user")

    {:ok, assign(socket, form: form, email_auth?: TannhauserGate.Features.email_auth?()),
     temporary_assigns: [form: form]}
  end
end
