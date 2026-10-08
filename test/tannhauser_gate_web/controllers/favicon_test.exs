defmodule TannhauserGateWeb.FaviconTest do
  use TannhauserGateWeb.ConnCase, async: true

  test "the root layout declares each local favicon format", %{conn: conn} do
    document =
      conn
      |> get(~p"/users/log_in")
      |> html_response(200)
      |> LazyHTML.from_document()

    for {path, rel, sizes} <- [
          {"/favicon.svg", "icon", "any"},
          {"/favicon.ico", "icon", "16x16 32x32 48x48"},
          {"/images/favicon-16.png", "icon", "16x16"},
          {"/images/favicon-32.png", "icon", "32x32"},
          {"/images/apple-touch-icon.png", "apple-touch-icon", "180x180"}
        ] do
      assert [_] =
               document
               |> LazyHTML.query("head link[href='#{path}'][rel='#{rel}'][sizes='#{sizes}']")
               |> LazyHTML.to_tree()
    end
  end

  test "PNG icons are served with their declared dimensions", %{conn: conn} do
    for {path, size} <- [
          {"/images/favicon-16.png", 16},
          {"/images/favicon-32.png", 32},
          {"/images/apple-touch-icon.png", 180}
        ] do
      response = get(conn, path)
      assert [content_type] = get_resp_header(response, "content-type")
      assert content_type =~ "image/png"
      assert png_dimensions(response(response, 200)) == {size, size}
    end
  end

  test "the conventional ICO URL serves all three PNG-backed icon sizes", %{conn: conn} do
    conn = get(conn, ~p"/favicon.ico")
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "image/"
    ico = response(conn, 200)
    assert <<0::little-16, 1::little-16, 3::little-16, entries::binary>> = ico

    for {size, index} <- Enum.with_index([16, 32, 48]) do
      entry = binary_part(entries, index * 16, 16)

      assert <<^size, ^size, 0, 0, 1::little-16, 32::little-16, length::little-32,
               offset::little-32>> = entry

      assert png_dimensions(binary_part(ico, offset, length)) == {size, size}
    end
  end

  defp png_dimensions(
         <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", width::32, height::32, _::binary>>
       ),
       do: {width, height}
end
