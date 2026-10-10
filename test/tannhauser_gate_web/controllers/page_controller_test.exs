defmodule TannhauserGateWeb.PageControllerTest do
  use TannhauserGateWeb.ConnCase

  import TannhauserGate.AccountsFixtures

  test "GET / redirects anonymous users to the login page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log_in"
  end

  test "GET / redirects logged in users to the GDR selection", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/gdrs"
  end
end
