defmodule TannhauserGateWeb.HealthController do
  use TannhauserGateWeb, :controller

  require Logger

  alias TannhauserGate.Repo

  def show(conn, _params) do
    case Repo.query("SELECT 1", [], timeout: 1_000, queue: false, log: false) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      {:error, _reason} ->
        unavailable(conn)
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      unavailable(conn)
  end

  defp unavailable(conn) do
    Logger.warning("Readiness check failed: database unavailable")

    conn
    |> put_status(:service_unavailable)
    |> json(%{status: "unavailable"})
  end
end
