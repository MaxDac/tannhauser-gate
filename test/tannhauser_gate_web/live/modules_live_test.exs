defmodule TannhauserGateWeb.ModulesLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Modules, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master}
  end

  describe "Stories.set_module_enabled/3" do
    test "toggles known modules and rejects unknown ones", %{story: story} do
      refute Stories.module_enabled?(story, :items)

      {:ok, story} = Stories.set_module_enabled(story, :items, true)
      assert Stories.module_enabled?(story, :items)
      assert Stories.module_enabled?(story, "items")
      assert Stories.module_enabled?(Stories.get_story(story.id), :items)

      {:ok, story} = Stories.set_module_enabled(story, "items", false)
      refute Stories.module_enabled?(story, :items)

      assert {:error, :unknown_module} = Stories.set_module_enabled(story, "nope", true)
    end

    test "sanitize keeps only known boolean modules" do
      assert Modules.sanitize(%{"items" => true, "x" => true, guilds: "true", esiti: 1}) ==
               %{"items" => true, "guilds" => true, "esiti" => false}
    end
  end

  describe "GM modules tab" do
    test "the GDR admin turns modules on and off", %{story: story, gm: gm} do
      {:ok, lv, _} = live(log_in_user(build_conn(), gm), ~p"/g/#{story}/gm/modules")

      for module <- Modules.all() do
        assert has_element?(lv, "#module-#{module.key}")
      end

      assert has_element?(lv, "#module-toggle-items[aria-checked=false]")
      lv |> element("#module-toggle-items") |> render_click()
      assert has_element?(lv, "#module-toggle-items[aria-checked=true]")
      assert Stories.module_enabled?(Stories.get_story(story.id), :items)

      lv |> element("#module-toggle-items") |> render_click()
      refute Stories.module_enabled?(Stories.get_story(story.id), :items)
    end

    test "masters cannot reach the modules tab", %{story: story, master: master} do
      assert {:error, {:redirect, %{to: to}}} =
               live(log_in_user(build_conn(), master), ~p"/g/#{story}/gm/modules")

      assert to == ~p"/g/#{story}"
    end
  end
end
