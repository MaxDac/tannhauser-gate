defmodule TannhauserGateWeb.PageControllerTest do
  use TannhauserGateWeb.ConnCase

  import TannhauserGate.AccountsFixtures

  test "GET / redirects anonymous users to the login page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log_in"
  end

  test "GET / redirects logged in users to their characters", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/characters"
  end
end
