defmodule TannhauserGateWeb.PageController do
  use TannhauserGateWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/characters")
    else
      redirect(conn, to: ~p"/users/log_in")
    end
  end
end
