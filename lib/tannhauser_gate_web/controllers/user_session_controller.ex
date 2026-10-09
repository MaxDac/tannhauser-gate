defmodule TannhauserGateWeb.UserSessionController do
  use TannhauserGateWeb, :controller

  alias TannhauserGate.Accounts
  alias TannhauserGateWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params}, info) do
    # The registration form posts its `username` field, the login form posts `login`.
    %{"password" => password} = user_params
    login = user_params["login"] || user_params["username"] || ""

    if user = Accounts.get_user_by_login_and_password(login, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the account exists.
      conn
      |> put_flash(:error, "Invalid username or password")
      |> put_flash(:login, String.slice(login, 0, 160))
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
