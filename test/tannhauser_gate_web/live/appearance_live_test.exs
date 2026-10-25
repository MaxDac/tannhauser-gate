defmodule TannhauserGateWeb.AppearanceLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.GameFixtures

  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Themes

  setup %{conn: conn} do
    {story, gm} = gdr_fixture()
    %{conn: log_in_user(conn, gm), story: story}
  end

  test "all eight presets preview without changing the saved game or outer shell", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/g/#{ctx.story}/gm/theme")

    for theme <- Themes.presets() do
      view |> element("#theme-preset-#{theme}") |> render_click()
      assert has_element?(view, "#theme-preset-#{theme}[aria-pressed='true']")
      assert has_element?(view, "#theme-preview[data-theme='#{theme}']")
      assert has_element?(view, "#app-shell[data-theme='#{ctx.story.theme}']")
      assert Stories.get_story!(ctx.story.id).theme == ctx.story.theme
    end

    assert has_element?(view, "#preview-primary.btn-primary")
    assert has_element?(view, "#preview-chat-body .chat-speech")
    assert has_element?(view, "#preview-disabled[disabled]")
    assert has_element?(view, "#preview-error[aria-invalid='true']")
  end

  test "saves appearance and retains it after navigation", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/g/#{ctx.story}/gm/theme")

    view
    |> form("#theme-form",
      story: %{
        theme: "nocturne",
        control_style: %{corners: "round", density: "compact", effects: "soft"},
        theme_overrides: %{primary: "#ccddff"}
      }
    )
    |> render_submit()

    updated = Stories.get_story!(ctx.story.id)
    assert updated.theme == "nocturne"

    assert updated.control_style == %{
             "corners" => "round",
             "density" => "compact",
             "effects" => "soft"
           }

    assert updated.theme_overrides == %{"primary" => "#ccddff"}
    assert has_element?(view, "#app-shell[data-theme='nocturne']")

    {:ok, view, _} = live(ctx.conn, ~p"/g/#{ctx.story}")

    assert has_element?(
             view,
             "#app-shell[style*='--radius-field:1.2rem'][style*='--color-primary:#ccddff']"
           )
  end

  test "reset clears overrides in the preview, saving remains explicit", ctx do
    {:ok, updated} =
      Stories.update_story_as_gm(ctx.story, %{
        theme: "azure",
        control_style: %{"corners" => "round"},
        theme_overrides: %{"primary" => "#aabbcc"}
      })

    {:ok, view, _} = live(ctx.conn, ~p"/g/#{updated}/gm/theme")
    view |> element("#theme-reset") |> render_click()
    assert has_element?(view, "#theme-preview[style*='--radius-field:0.3rem']")
    assert Stories.get_story!(updated.id).control_style == %{"corners" => "round"}
    view |> form("#theme-form") |> render_submit()
    assert Stories.get_story!(updated.id).control_style == %{}
    assert Stories.get_story!(updated.id).theme_overrides == %{}
  end

  test "shows contrast feedback while keeping changes scoped to the preview", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/g/#{ctx.story}/gm/theme")

    view
    |> form("#theme-form", story: %{theme_overrides: %{primary: "#101715"}})
    |> render_change()

    assert has_element?(view, "#theme-preview [role='status']")
    assert Stories.get_story!(ctx.story.id).theme_overrides == %{}
  end

  test "invalid choices return errors and do not persist", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/g/#{ctx.story}/gm/theme")
    render_submit(view, "save_story", %{"story" => %{"control_style" => %{"density" => "tiny"}}})
    assert has_element?(view, "#control-style-errors")
    assert Stories.get_story!(ctx.story.id).control_style == %{}
  end
end
