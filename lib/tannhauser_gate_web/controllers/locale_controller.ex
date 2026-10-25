defmodule TannhauserGateWeb.LocaleController do
  use TannhauserGateWeb, :controller

  def update(conn, params) do
    return_to = params["return_to"] || referrer_path(conn)

    conn
    |> put_session(:locale, TannhauserGateWeb.Locale.normalize(params["locale"]))
    |> redirect(to: return_path(return_to))
  end

  defp referrer_path(conn) do
    with [referrer] <- get_req_header(conn, "referer"),
         uri = URI.parse(referrer),
         true <-
           uri.host == conn.host and uri.scheme == to_string(conn.scheme) and
             uri.port == conn.port do
      (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")
    else
      _ -> "/"
    end
  end

  defp return_path("/" <> rest = path) do
    if String.starts_with?(rest, "/") or Regex.match?(~r/[\x00-\x20\x7f\\]/, path) do
      "/"
    else
      path
    end
  end

  defp return_path(_path), do: "/"
end
