defmodule TannhauserGateWeb.HealthControllerTest do
  use TannhauserGateWeb.ConnCase, async: true

  test "anonymous requests can check database readiness", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "location") == []
  end

  test "readiness does not require a browser session", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
