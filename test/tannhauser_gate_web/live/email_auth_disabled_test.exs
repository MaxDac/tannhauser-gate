defmodule TannhauserGateWeb.EmailAuthDisabledTest do
  # Mutates the global feature flag, so it can't run async.
  use TannhauserGateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import TannhauserGate.AccountsFixtures

  alias TannhauserGate.Accounts

  setup do
    Application.put_env(:tannhauser_gate, :feature_email_auth, false)
    on_exit(fn -> Application.put_env(:tannhauser_gate, :feature_email_auth, true) end)
    :ok
  end

  test "registration sends no email and leaves the account unconfirmed", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/register")
    attrs = valid_user_attributes()
    form = form(lv, "#registration_form", user: attrs)
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/gdrs"
    assert_no_email_sent()
    assert %{confirmed_at: nil} = Accounts.get_user_by_email(attrs.email)
  end

  test "registration requires a username", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/register")

    html =
      lv
      |> form("#registration_form", user: valid_user_attributes(username: ""))
      |> render_change()

    assert html =~ "can&#39;t be blank"
  end

  test "login uses the username only", %{conn: conn} do
    user = user_fixture()

    by_email =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"login" => user.email, "password" => valid_user_password()}
      })

    assert redirected_to(by_email) == ~p"/users/log_in"

    by_username =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"login" => user.username, "password" => valid_user_password()}
      })

    assert redirected_to(by_username) == ~p"/gdrs"
  end

  test "login page hides the forgot password link", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/log_in")
    refute html =~ "Forgot your password?"
  end

  test "email pages redirect to login", %{conn: conn} do
    for path <- [~p"/users/reset_password", ~p"/users/confirm", ~p"/users/confirm/sometoken"] do
      assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, path)
    end
  end

  test "settings changes the email without sending mail", %{conn: conn} do
    user = user_fixture()
    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")
    new_email = unique_user_email()

    lv
    |> form("#email_form", %{
      "current_password" => valid_user_password(),
      "user" => %{"email" => new_email}
    })
    |> render_submit()

    assert_no_email_sent()
    assert Accounts.get_user!(user.id).email == new_email
  end
end

defmodule TannhauserGateWeb.EmailAuthEnabledLoginTest do
  use TannhauserGateWeb.ConnCase, async: true

  import TannhauserGate.AccountsFixtures

  test "login accepts the email when the flag is on", %{conn: conn} do
    user = user_fixture()

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"login" => user.email, "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/gdrs"
  end
end
