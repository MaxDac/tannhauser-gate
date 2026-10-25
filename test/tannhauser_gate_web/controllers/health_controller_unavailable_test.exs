defmodule TannhauserGateWeb.HealthControllerUnavailableTest do
  use TannhauserGateWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  alias TannhauserGate.Repo

  test "reports 503 when the database can't answer", %{conn: conn} do
    # A failed statement aborts the surrounding transaction: every following
    # query, including the readiness probe, errors until the rollback.
    Repo.transaction(fn ->
      assert {:error, _} = Repo.query("SELECT 1/0", [], log: false)

      log =
        capture_log(fn ->
          conn = get(conn, ~p"/health")
          assert json_response(conn, 503) == %{"status" => "unavailable"}
        end)

      assert log =~ "Readiness check failed: database unavailable"
      Repo.rollback(:done)
    end)
  end
end
