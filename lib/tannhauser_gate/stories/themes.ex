defmodule TannhauserGate.Stories.Themes do
  @moduledoc """
  Visual themes a game master can pick for their GDR.

  Eight daisyUI presets, with allowlisted colour and control overrides.
  Preset IDs remain stable so changing the display names never breaks a GDR.
  """

  @themes [
    %{
      id: "tannhauser",
      name: "Quiet noir",
      game: "Tannhauser Gate",
      description: "Smoked jade, softened edges and cinematic restraint.",
      colors: ~w(#101715 #151e1b #1e2b25 #dce7df #a4d5b5 #91a79a #c1e9ce),
      controls: %{"corners" => "soft", "density" => "comfortable", "effects" => "flat"}
    },
    %{
      id: "azure",
      name: "Neon circuit",
      game: "Neon Republic",
      description: "Electric cyan, precise edges and a quiet accent light.",
      colors: ~w(#0d171c #142129 #1c303c #d5e9ed #78cfe0 #8faeb8 #a6e7ef),
      controls: %{"corners" => "sharp", "density" => "compact", "effects" => "accent"}
    },
    %{
      id: "sepia",
      name: "Last light",
      game: "Arkham Adrift",
      description: "Lamplight gold and aged ink: warmth in the dark.",
      colors: ~w(#1b1914 #242119 #332d23 #eae3d2 #d6c291 #ada48d #f1dfa9),
      controls: %{"corners" => "soft", "density" => "comfortable", "effects" => "soft"}
    },
    %{
      id: "nocturne",
      name: "Velvet night",
      game: "Toronto by Night",
      description: "Oxblood, dusty rose and nocturnal elegance.",
      colors: ~w(#190f15 #24151e #37202c #efdae4 #e8a1b4 #b693a4 #f3c9d7),
      controls: %{"corners" => "round", "density" => "comfortable", "effects" => "accent"}
    },
    %{
      id: "midnight",
      name: "Midnight glass",
      game: nil,
      description: "Cool violet and softly layered, rounded surfaces.",
      colors: ~w(#12151e #191e2a #252c3d #e1e5f1 #b1bcf5 #9ea7c2 #d4dcff),
      controls: %{"corners" => "round", "density" => "comfortable", "effects" => "soft"}
    },
    %{
      id: "ember",
      name: "After hours",
      game: nil,
      description: "Amber and espresso, intimate and understated.",
      colors: ~w(#1b1512 #241c17 #35281f #eee1d5 #e7ba88 #b8a08a #f4d5af),
      controls: %{"corners" => "sharp", "density" => "compact", "effects" => "accent"}
    },
    %{
      id: "crimson",
      name: "Red ledger",
      game: nil,
      description: "Muted vermilion and charcoal for intrigue and danger.",
      colors: ~w(#1b1011 #261719 #382225 #f0dddc #ee9f98 #b89a98 #f6c9c0),
      controls: %{"corners" => "sharp", "density" => "comfortable", "effects" => "flat"}
    },
    %{
      id: "silver",
      name: "Moonsteel",
      game: nil,
      description: "Silver-blue, slate and clean, quiet controls.",
      colors: ~w(#12171d #1a212a #263240 #e0e7ee #b7cbdc #98aabb #d7e7f3),
      controls: %{"corners" => "round", "density" => "comfortable", "effects" => "flat"}
    }
  ]
  @presets Enum.map(@themes, & &1.id)
  @color_keys ~w(primary secondary accent base-100 base-200 base-300 base-content)
  @palette_keys ~w(base-100 base-200 base-300 base-content primary secondary accent)
  @control_options %{
    "corners" => [{"Precise", "sharp"}, {"Softened", "soft"}, {"Rounded", "round"}],
    "density" => [{"Comfortable", "comfortable"}, {"Compact", "compact"}],
    "effects" => [
      {"Quiet / flat", "flat"},
      {"Soft atmosphere", "soft"},
      {"Accent light", "accent"}
    ]
  }
  @hex ~r/\A#[0-9a-fA-F]{6}\z/

  def presets, do: @presets
  def all, do: @themes
  def options, do: Enum.map(@themes, &{&1.name, &1.id})
  def control_options, do: @control_options
  def color_keys, do: @color_keys
  def default, do: "tannhauser"
  def platform, do: "platform"

  def preset(id), do: Enum.find(@themes, &(&1.id == id)) || hd(@themes)

  def palette(id), do: Map.new(Enum.zip(@palette_keys, preset(id).colors))

  def controls(id, overrides) do
    Map.merge(preset(id).controls, sanitize_controls(overrides))
  end

  def sanitize_controls(overrides) when is_map(overrides) do
    Map.new(
      for {key, value} <- overrides,
          {_, ^value} <- Map.get(@control_options, key, []),
          do: {key, value}
    )
  end

  def sanitize_controls(_), do: %{}

  def validate_controls(overrides) do
    Enum.flat_map(overrides, fn
      {_key, value} when value in [nil, ""] ->
        []

      {key, value} ->
        if Enum.any?(Map.get(@control_options, key, []), &(elem(&1, 1) == value)),
          do: [],
          else: [control_style: {"has an invalid %{setting} choice", [setting: key]}]
    end)
  end

  @doc "Whether `value` is a valid `#rrggbb` colour."
  def hex?(value) when is_binary(value), do: Regex.match?(@hex, value)
  def hex?(_), do: false

  @doc """
  Keeps only the known keys with valid hex colours; blank values are dropped.
  """
  def sanitize_overrides(overrides) when is_map(overrides) do
    for {key, value} <- overrides,
        key = to_string(key),
        key in @color_keys,
        is_binary(value),
        hex?(String.trim(value)),
        into: %{},
        do: {key, String.trim(value)}
  end

  def sanitize_overrides(_), do: %{}

  @doc """
  The inline `style` value applying the overrides as CSS variables.
  """
  def style(overrides) do
    overrides
    |> sanitize_overrides()
    |> Enum.sort()
    |> Enum.map_join(";", fn {key, value} -> "--color-#{key}:#{value}" end)
  end

  @doc "Complete scoped daisyUI tokens, including readable button foregrounds."
  def style(id, overrides, control_style) do
    colors = Map.merge(palette(id), sanitize_overrides(overrides))
    controls = controls(id, control_style)

    colors =
      Enum.reduce(~w(primary secondary accent), colors, fn key, colors ->
        Map.put(colors, "#{key}-content", foreground(colors[key]))
      end)

    [style_colors(colors), control_tokens(controls)]
    |> Enum.join(";")
  end

  def contrast_warnings(id, overrides) do
    colors = Map.merge(palette(id), sanitize_overrides(overrides))

    for {key, label} <- [{"primary", "Accent"}, {"base-content", "Body text"}],
        Enum.any?(~w(base-100 base-200 base-300), &(contrast(colors[key], colors[&1]) < 4.5)),
        do:
          "#{label} has low contrast against a surface. Choose a lighter text colour or darker surface."
  end

  defp style_colors(colors) do
    colors
    |> Enum.sort()
    |> Enum.map_join(";", fn {key, value} -> "--color-#{key}:#{value}" end)
  end

  defp control_tokens(controls) do
    {selector, field, box} =
      case controls["corners"] do
        "sharp" -> {"0.2rem", "0.3rem", "0.6rem"}
        "soft" -> {"0.4rem", "0.65rem", "1rem"}
        "round" -> {"1rem", "1.2rem", "1.4rem"}
      end

    {size, height} =
      if controls["density"] == "compact",
        do: {"0.225rem", "2.25rem"},
        else: {"0.25rem", "2.75rem"}

    shadow =
      case controls["effects"] do
        "flat" -> "none"
        "soft" -> "0 4px 16px rgb(0 0 0 / 0.12)"
        "accent" -> "0 0 18px color-mix(in oklab,var(--color-primary) 12%,transparent)"
      end

    "--radius-selector:#{selector};--radius-field:#{field};--radius-box:#{box};" <>
      "--size-field:#{size};--control-height:#{height};--control-shadow:#{shadow};--depth:0;--noise:0"
  end

  defp foreground(color) do
    if contrast(color, "#102017") >= contrast(color, "#ffffff"),
      do: "#102017",
      else: "#ffffff"
  end

  defp contrast(a, b) do
    a = luminance(a)
    b = luminance(b)
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
  end

  defp luminance("#" <> hex) do
    [red, green, blue] =
      for <<channel::binary-size(2) <- hex>> do
        value = String.to_integer(channel, 16) / 255
        if value <= 0.04045, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)
      end

    red * 0.2126 + green * 0.7152 + blue * 0.0722
  end
end
