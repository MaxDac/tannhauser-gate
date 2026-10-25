defmodule TannhauserGateWeb.GuildsLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Guilds, Repo, Stories}
  alias TannhauserGate.Forum.Section

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp with_guilds(ctx) do
    story = enable_modules(ctx.story, [:guilds])
    character = character_fixture(ctx.player, story)
    {:ok, police} = Guilds.create_guild(story, %{name: "Police", open_join: true})
    {:ok, cadet} = Guilds.create_rank(police, %{name: "Cadet", salary: 20, position: 0})

    {:ok, captain} =
      Guilds.create_rank(police, %{name: "Captain", salary: 80, position: 1, leader: true})

    {:ok, echo} =
      Guilds.create_guild(story, %{name: "Echo Underground", secret: true, open_join: false})

    Map.merge(ctx, %{
      story: story,
      character: character,
      police: police,
      cadet: cadet,
      captain: captain,
      echo: echo
    })
  end

  describe "module disabled" do
    test "pages redirect and links are hidden", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/master")
      refute has_element?(lv, "#nav-guilds")
      refute has_element?(lv, "#master-guilds")

      for path <- [
            ~p"/g/#{ctx.story}/guilds",
            ~p"/g/#{ctx.story}/guilds/1",
            ~p"/g/#{ctx.story}/master/guilds"
          ] do
        assert {:error, {:redirect, %{to: to}}} = live(conn_for(ctx.gm), path)
        assert to == ~p"/g/#{ctx.story}"
      end
    end
  end

  describe "player pages" do
    setup :with_guilds

    test "secret guilds are hidden from strangers", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guilds")
      assert has_element?(lv, "#nav-guilds")
      assert has_element?(lv, "#guild-#{ctx.police.id}")
      refute has_element?(lv, "#guild-#{ctx.echo.id}")
      refute has_element?(lv, "#manage-guilds")

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guilds/#{ctx.echo}")

      assert to == ~p"/g/#{ctx.story}/guilds"

      {other_story, _} = gdr_fixture()
      {:ok, foreign} = Guilds.create_guild(other_story, %{name: "Foreign"})

      assert {:error, {:live_redirect, _}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guilds/#{foreign}")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/guilds")
      assert has_element?(lv, "#guild-#{ctx.echo.id}")
      assert has_element?(lv, "#manage-guilds")
    end

    test "a player asks to join, a master approves, the sheet shows it", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guilds/#{ctx.police}")
      refute has_element?(lv, "#guild-management")
      lv |> element("#request-join") |> render_click()
      assert has_element?(lv, "#cancel-request")

      [pending] = Guilds.list_pending(ctx.police)
      {:ok, mlv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/guilds/#{ctx.police}")
      assert has_element?(mlv, "#pending-#{pending.id}")
      mlv |> element("#approve-#{pending.id}") |> render_click()
      assert has_element?(mlv, "#member-#{pending.id}")
      assert has_element?(mlv, "#guild-logs", "joined")

      mlv
      |> form("#rank-form-#{pending.id}", %{membership_id: pending.id, rank_id: ctx.captain.id})
      |> render_change()

      assert Guilds.get_membership(ctx.police, pending.id).rank_id == ctx.captain.id

      {:ok, slv, _} =
        live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      assert has_element?(slv, "#character-guild-#{ctx.police.id}", "Captain")

      # A leader now manages the guild.
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guilds/#{ctx.police}")
      assert has_element?(lv, "#guild-management")
      lv |> element("#leave-guild") |> render_click()
      refute Guilds.active_member_user?(ctx.player, ctx.police.id)
    end

    test "invitations to secret guilds are answered from the index", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/guilds/#{ctx.echo}")

      lv
      |> form("#invite-form", invite: %{character_id: ctx.character.id})
      |> render_submit()

      [invitation] = Guilds.list_pending(ctx.echo)

      {:ok, plv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guilds")
      assert has_element?(plv, "#guild-#{ctx.echo.id}")
      plv |> element("#accept-invitation-#{invitation.id}") |> render_click()
      assert has_element?(plv, "#guild-status-#{ctx.echo.id}", "Member")

      # The secret membership doesn't show on the sheet to strangers.
      {:ok, slv, _} =
        live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/characters/#{ctx.character}")

      refute has_element?(slv, "#character-guilds")
    end

    test "members are hidden in secret guilds, shown in public ones", ctx do
      {:ok, _} = Guilds.enrol(ctx.master, ctx.story, ctx.echo, ctx.character.id)
      stranger = user_fixture()
      character_fixture(stranger, ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/guilds/#{ctx.echo}")
      assert has_element?(lv, "#guild-members", ctx.character.name)

      {:ok, lv, _} = live(conn_for(stranger), ~p"/g/#{ctx.story}/guilds/#{ctx.police}")
      assert has_element?(lv, "#members-empty")
    end
  end

  describe "master pages" do
    setup :with_guilds

    test "players cannot reach the guild management", ctx do
      assert {:error, {:redirect, _}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/guilds")
    end

    test "a master creates a guild and its ranks", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master")
      assert has_element?(lv, "#master-guilds")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/guilds")

      lv
      |> form("#guild-form", guild: %{name: "Ascendant Security", description: "**Corp**"})
      |> render_submit()

      guild = Enum.find(Guilds.list_guilds(ctx.story), &(&1.name == "Ascendant Security"))
      assert guild
      assert has_element?(lv, "#master-guild-#{guild.id}")

      lv |> element("#edit-guild-#{guild.id}") |> render_click()

      lv
      |> form("#rank-form", rank: %{name: "Guard", salary: 30, position: 0})
      |> render_submit()

      assert [%{name: "Guard", salary: 30}] = Guilds.get_guild(ctx.story, guild.id).ranks

      lv |> element("#delete-guild-#{guild.id}") |> render_click()
      refute Guilds.get_guild(ctx.story, guild.id)
    end
  end

  describe "GM integration" do
    setup :with_guilds

    test "guild forum sections and guild rooms", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/forum")

      lv
      |> form("#section-form",
        section: %{name: "Den", visibility: "guild", guild_id: ctx.echo.id}
      )
      |> render_submit()

      section = Repo.get_by!(Section, story_id: ctx.story.id, name: "Den")
      assert section.guild_id == ctx.echo.id
      assert has_element?(lv, "#section-guild-#{section.id}")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/forum")
      refute render(lv) =~ "Den"

      location = location_fixture(ctx.story, %{guild_id: ctx.police.id})
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{location}")
      assert has_element?(lv, "#guild-locked")
      assert has_element?(lv, "#guild-badge", "Police")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/map")
      assert has_element?(lv, "#room-guild-#{location.id}", "Police")

      {:ok, _} = Guilds.enrol(ctx.master, ctx.story, ctx.police, ctx.character.id)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{location}")
      refute has_element?(lv, "#guild-locked")
      refute has_element?(lv, "#private-locked")
    end

    test "the GDR admin sets the max guilds per character", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm")

      lv
      |> form("#general-form", story: %{max_guilds_per_character: 3})
      |> render_submit()

      assert Stories.get_story!(ctx.story.id).max_guilds_per_character == 3
    end
  end
end
