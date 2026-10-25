defmodule TannhauserGateWeb.MapPins do
  @moduledoc """
  Places the pins of a GDR map and lays out their name labels.

  Pins sit on each room's centroid, as a percentage of the map. Labels are
  sized relative to the map width (CSS `cqw` units of `.map-frame`), so their
  footprint can be computed here once: each label tries below, above, right
  and left of its pin (centred, then shifted sideways) and takes the first
  spot that stays on the map and clears every pin and every label already
  placed. A label with no free spot is shown only on hover/focus.

  All the geometry below is in `cqw`: 100 is the map width.
  """

  alias TannhauserGate.Stories.Location

  # Must match `.map-pin-label` in app.css.
  @font 1.6
  @char_width 0.64 * @font
  @label_padding 1.1 * @font + 0.2
  @label_height 1.6 * @font + 0.2
  # The 44px pin box measured on the narrowest map that shows labels (560px).
  @pin_half_width 3.0
  @pin_height 8.0
  @gap 0.4
  # Labels keep away from the sides of other pins so each reads as its own pin's.
  @pin_clearance 2.0
  @margin 0.4

  @type label :: %{x: float(), y: float()} | nil
  @type pin :: %{
          location: Location.t(),
          index: pos_integer(),
          left: float(),
          top: float(),
          label: label()
        }

  @doc "Lays out the pins of `locations` on a `width` x `height` map."
  @spec layout([Location.t()], pos_integer(), pos_integer()) :: [pin()]
  def layout(locations, width, height) do
    map_height = height * 100 / width

    tips =
      locations
      |> Enum.with_index(1)
      |> Enum.map(fn {location, index} ->
        {x, y} = Location.centroid(location)
        {location, index, x * 100 / width, y * 100 / width}
      end)

    pins = Enum.map(tips, fn {_, _, x, y} -> pin_box(x, y) end)

    # Each label may not cover another pin; the most constrained labels pick
    # their spot first, then every placed label blocks the following ones.
    candidates =
      Map.new(tips, fn {location, index, x, y} ->
        others = pins |> List.delete(pin_box(x, y)) |> Enum.map(&widen/1)

        spots =
          location.name
          |> label_spots(x, y)
          |> Enum.filter(fn rect ->
            inside?(rect, map_height) and not Enum.any?(others, &overlap?(rect, &1))
          end)

        {index, spots}
      end)

    labels =
      candidates
      |> Enum.sort_by(fn {index, spots} -> {length(spots), index} end)
      |> place_labels(%{})

    Enum.map(tips, fn {location, index, x, y} ->
      rect = labels[index]

      %{
        location: location,
        index: index,
        left: Float.round(x, 3),
        top: Float.round(y * 100 / map_height, 3),
        label: rect && %{x: Float.round(rect.x - x, 2), y: Float.round(rect.y - y, 2)}
      }
    end)
  end

  @doc "Inline style for a pin: its position and colour."
  @spec pin_style(pin()) :: String.t()
  def pin_style(%{left: left, top: top, location: location}),
    do: "left: #{left}%; top: #{top}%; --pin-color: #{location.color}"

  @doc "Inline style for a placed label: its offset from the pin tip."
  @spec label_style(pin()) :: String.t() | nil
  def label_style(%{label: nil}), do: nil
  def label_style(%{label: %{x: x, y: y}}), do: "--label-x: #{x}; --label-y: #{y}"

  defp pin_box(x, y),
    do: %{x: x - @pin_half_width, y: y - @pin_height, w: 2 * @pin_half_width, h: @pin_height}

  defp widen(rect), do: %{rect | x: rect.x - @pin_clearance, w: rect.w + 2 * @pin_clearance}

  # Each label takes its most preferred free spot, unless that spot would leave
  # a later label with no free spot at all; then it takes the spot that starves
  # the fewest later labels.
  defp place_labels([], placed), do: placed

  defp place_labels([{index, spots} | rest], placed) do
    taken = Map.values(placed)

    case Enum.reject(spots, &blocked?(&1, taken)) do
      [] ->
        place_labels(rest, placed)

      free ->
        pending =
          Enum.map(rest, fn {_, later} -> Enum.reject(later, &blocked?(&1, taken)) end)

        rect = Enum.min_by(free, &starved(&1, pending))
        place_labels(rest, Map.put(placed, index, rect))
    end
  end

  defp blocked?(rect, taken), do: Enum.any?(taken, &overlap?(rect, &1))

  defp starved(rect, pending) do
    Enum.count(pending, fn later -> later != [] and Enum.all?(later, &overlap?(rect, &1)) end)
  end

  # Candidate spots in order of preference: centred below/above the pin,
  # beside it, then below/above shifted sideways.
  defp label_spots(name, x, y) do
    w = String.length(name) * @char_width + @label_padding
    h = @label_height
    beside = y - @pin_height / 2 - h / 2
    below = y + 0.5
    above = y - @pin_height - 0.2 - h

    [
      {clamp(x - w / 2, w), below},
      {clamp(x - w / 2, w), above},
      {x + @pin_half_width + 0.4, beside},
      {x - @pin_half_width - 0.4 - w, beside},
      {x - @pin_half_width, below},
      {x + @pin_half_width - w, below},
      {x - @pin_half_width, above},
      {x + @pin_half_width - w, above}
    ]
    |> Enum.map(fn {rx, ry} -> %{x: rx, y: ry, w: w, h: h} end)
  end

  defp clamp(x, w), do: x |> max(@margin) |> min(100 - @margin - w)

  defp inside?(rect, map_height) do
    rect.x >= @margin and rect.y >= @margin and rect.x + rect.w <= 100 - @margin and
      rect.y + rect.h <= map_height - @margin
  end

  defp overlap?(a, b) do
    a.x < b.x + b.w + @gap and b.x < a.x + a.w + @gap and
      a.y < b.y + b.h + @gap and b.y < a.y + a.h + @gap
  end
end
