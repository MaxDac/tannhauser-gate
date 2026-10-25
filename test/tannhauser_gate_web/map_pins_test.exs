defmodule TannhauserGateWeb.MapPinsTest do
  use ExUnit.Case, async: true

  alias TannhauserGate.Seeds.{ArkhamAdrift, DefaultGdr, NeonRepublic, TorontoByNight}
  alias TannhauserGate.Stories.Location
  alias TannhauserGateWeb.MapPins

  # Label footprint in cqw, as in MapPins / `.map-pin-label`.
  @char_width 0.64 * 1.6
  @label_padding 1.1 * 1.6 + 0.2
  @label_height 1.6 * 1.6 + 0.2

  defp location(id, name, area, color \\ "#123456"),
    do: %Location{id: id, name: name, area: area, color: color}

  defp square(cx, cy, r \\ 20),
    do: "#{cx - r},#{cy - r} #{cx + r},#{cy - r} #{cx + r},#{cy + r} #{cx - r},#{cy + r}"

  defp label_box(%{label: %{x: dx, y: dy}, left: left, top: top, location: location}, map_h) do
    x = left + dx
    y = top * map_h / 100 + dy
    w = String.length(location.name) * @char_width + @label_padding
    %{x: x, y: y, w: w, h: @label_height}
  end

  defp overlap?(a, b),
    do: a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h

  test "places pins on room centroids as map percentages" do
    pins =
      MapPins.layout(
        [
          location(1, "North", "100,100 300,100 300,300 100,300"),
          location(2, "South", square(600, 455))
        ],
        1000,
        700
      )

    assert [%{index: 1, left: 20.0, top: 28.571}, %{index: 2, left: 60.0, top: 65.0}] = pins
  end

  test "a lone pin gets its label centred below it" do
    [pin] = MapPins.layout([location(1, "Bar", square(500, 350))], 1000, 700)

    width = 3 * @char_width + @label_padding
    assert_in_delta pin.label.x, -width / 2, 0.01
    assert pin.label.y > 0
    assert MapPins.label_style(pin) =~ "--label-x: "
    assert MapPins.pin_style(pin) == "left: 50.0%; top: 50.0%; --pin-color: #123456"
  end

  test "labels flip above or aside when the bottom edge is too close" do
    [pin] = MapPins.layout([location(1, "Dock", square(500, 690, 5))], 1000, 700)

    assert pin.label.y < 0
  end

  test "a label with no room on the map stays hover-only" do
    crowded =
      for i <- 1..12 do
        location(
          i,
          "A rather long room name #{i}",
          square(470 + rem(i, 4) * 20, 330 + div(i, 4) * 20, 5)
        )
      end

    pins = MapPins.layout(crowded, 1000, 700)

    assert Enum.any?(pins, &is_nil(&1.label))
    assert Enum.all?(pins, fn pin -> is_nil(pin.label) == is_nil(MapPins.label_style(pin)) end)
  end

  for module <- [DefaultGdr, NeonRepublic, ArkhamAdrift, TorontoByNight] do
    test "#{inspect(module)} labels every pin without overlaps" do
      locations =
        unquote(module).locations()
        |> Enum.with_index(1)
        |> Enum.map(fn {attrs, id} -> location(id, attrs.name, attrs.area, attrs.color) end)

      pins = MapPins.layout(locations, 1000, 700)
      map_h = 70.0

      assert Enum.all?(pins, & &1.label)

      boxes = Enum.map(pins, &label_box(&1, map_h))

      for box <- boxes do
        assert box.x >= 0 and box.x + box.w <= 100
        assert box.y >= 0 and box.y + box.h <= map_h
      end

      for {a, i} <- Enum.with_index(boxes), {b, j} <- Enum.with_index(boxes), i < j do
        refute overlap?(a, b)
      end
    end
  end
end
