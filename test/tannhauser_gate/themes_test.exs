defmodule TannhauserGate.ThemesTest do
  use TannhauserGate.DataCase, async: true

  alias TannhauserGate.Stories.{Story, Themes}

  test "eight stable GDR presets are distinct from the platform theme" do
    assert length(Themes.all()) == 8

    assert Enum.sort(Themes.presets()) ==
             Enum.sort(~w(tannhauser azure sepia nocturne midnight ember crimson silver))

    refute Themes.platform() in Themes.presets()
    assert length(Themes.options()) == 8
    assert Themes.preset("unknown").id == Themes.default()
  end

  test "each preset supplies safe colours and complete, valid control defaults" do
    for theme <- Themes.all() do
      assert Enum.all?(Themes.palette(theme.id), fn {_, color} -> Themes.hex?(color) end)
      assert Themes.validate_controls(theme.controls) == []
      assert Themes.controls(theme.id, nil) == theme.controls
      assert Themes.contrast_warnings(theme.id, %{}) == []
      assert Themes.style(theme.id, %{}, %{}) =~ "--color-primary-content:#102017"
    end
  end

  test "control overrides take precedence and only known choices reach CSS" do
    assert Themes.controls("azure", %{"density" => "comfortable"}) ==
             %{"corners" => "sharp", "density" => "comfortable", "effects" => "accent"}

    assert Themes.sanitize_controls(%{"corners" => "url(evil)", "effects" => "soft", "x" => "y"}) ==
             %{"effects" => "soft"}

    assert Themes.sanitize_controls(nil) == %{}
    assert Themes.validate_controls(%{"corners" => "", "density" => nil}) == []
    assert [_] = Themes.validate_controls(%{"corners" => "invalid"})
    assert [_] = Themes.validate_controls(%{"unknown" => "soft"})
  end

  test "every appearance option produces allowlisted tokens" do
    for theme <- Themes.presets(),
        {key, choices} <- Themes.control_options(),
        {_, value} <- choices do
      style = Themes.style(theme, %{}, %{key => value})
      assert style =~ "--radius-field:"
      assert style =~ "--size-field:"
      assert style =~ "--control-shadow:"
      refute style =~ "undefined"
    end
  end

  test "button text adjusts to dark and light custom accents and warns about low contrast" do
    assert Themes.style("tannhauser", %{"primary" => "#000000"}, %{}) =~
             "--color-primary-content:#ffffff"

    assert Themes.style("silver", %{"primary" => "#ffffff"}, %{}) =~
             "--color-primary-content:#102017"

    assert [_] = Themes.contrast_warnings("tannhauser", %{"primary" => "#101715"})
    assert [_] = Themes.contrast_warnings("tannhauser", %{"base-content" => "#101715"})

    assert Themes.style("azure", %{"primary" => "red;bad"}, %{"effects" => "evil"}) ==
             Themes.style("azure", %{}, %{})
  end

  test "story changesets persist only valid choices and reject malformed controls" do
    for theme <- Themes.presets() do
      changeset =
        Story.gm_changeset(%Story{}, %{
          name: "A game",
          theme: theme,
          control_style: %{"corners" => "round", "effects" => ""}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :control_style) == %{"corners" => "round"}
    end

    changeset =
      Story.gm_changeset(%Story{name: "A game"}, %{control_style: %{"density" => "tiny"}})

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :control_style)

    refute Story.gm_changeset(%Story{name: "A game"}, %{control_style: nil}).valid?
    refute Story.gm_changeset(%Story{name: "A game"}, %{control_style: "bad"}).valid?
  end
end
