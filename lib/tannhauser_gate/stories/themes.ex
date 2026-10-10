defmodule TannhauserGate.Stories.Themes do
  @moduledoc """
  Visual themes a game master can pick for their GDR.

  A theme is one of the presets defined in `assets/css/app.css` plus an
  optional map of colour overrides. Only hex colours for a fixed list of keys
  are accepted, so the values can safely be rendered in an inline style.
  """

  @presets ~w(tannhauser ember azure crimson)
  @color_keys ~w(primary secondary accent base-100 base-200 base-300 base-content)
  @hex ~r/\A#[0-9a-fA-F]{6}\z/

  def presets, do: @presets
  def color_keys, do: @color_keys
  def default, do: "tannhauser"
  def platform, do: "platform"

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
end
