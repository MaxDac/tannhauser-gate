defmodule TannhauserGateWeb.PlayerPagesEdgeLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Boards, Diary, Esiti, Guilds, Items, Repo, Sanctions, Stories}

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, gm: gm, master: master, player: user_fixture(), other: user_fixture()}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp mute!(ctx, user) do
    {:ok, _} =
      Sanctions.issue(ctx.master, ctx.story, %{
        "user_id" => user.id,
        "kind" => "mute",
        "reason" => "Rude",
        "duration" => "permanent"
      })

    :ok
  end

  defp entry!(ctx) do
    {:ok, entry} =
      Diary.create_entry(ctx.player, ctx.character, %{
        "title" => "Rainy night",
        "body" => "Wet.",
        "visibility" => "public"
      })

    entry
  end

  defp file!(ctx, attrs \\ %{}) do
    {:ok, esito} =
      Esiti.create_esito(
        ctx.player,
        ctx.story,
        Enum.into(attrs, %{
          "character_id" => to_string(ctx.character.id),
          "title" => "Night at the warehouse",
          "body" => "I sneak in."
        })
      )

    esito
  end

  defp show_path(ctx, esito), do: ~p"/g/#{ctx.story}/esiti/#{esito.id}"

  describe "diary page" do
    setup ctx do
      story = enable_modules(ctx.story, [:diary, :reports])
      character = character_fixture(ctx.player, story)

      %{
        story: story,
        character: character,
        path: ~p"/g/#{story}/characters/#{character}/diary"
      }
    end

    test "the editor validates, cancels and rejects a blank entry", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ctx.path)

      lv |> element("#diary-new-entry") |> render_click()
      lv |> form("#diary-form", entry: %{title: "", body: ""}) |> render_change()
      assert has_element?(lv, "#diary-form")

      lv |> element("#diary-cancel") |> render_click()
      refute has_element?(lv, "#diary-form")

      lv |> element("#diary-new-entry") |> render_click()
      lv |> form("#diary-form", entry: %{title: "", body: ""}) |> render_submit()
      assert has_element?(lv, "#diary-form")
      assert Diary.list_entries(ctx.character, ctx.player) == []
    end

    test "blanking the title of an entry keeps the editor open", ctx do
      entry = entry!(ctx)
      {:ok, lv, _} = live(conn_for(ctx.player), ctx.path)

      lv |> element("#diary-entry-#{entry.id}-edit") |> render_click()
      lv |> form("#diary-form", entry: %{title: "  "}) |> render_submit()

      assert has_element?(lv, "#diary-form")
      assert Diary.get_entry(ctx.character, entry.id).title == "Rainy night"
    end

    test "forged saves and deletes are refused", ctx do
      entry = entry!(ctx)

      {:ok, lv, _} = live(conn_for(ctx.player), ctx.path)
      render_hook(lv, "save_entry", %{"entry" => %{"title" => "X", "body" => "Y"}})
      assert has_element?(lv, "#flash-error", "That item does not exist.")

      render_hook(lv, "delete_entry", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", "That item does not exist.")

      {:ok, lv, _} = live(conn_for(ctx.other), ctx.path)
      refute has_element?(lv, "#diary-new-entry")

      render_hook(lv, "new_entry", %{})
      assert has_element?(lv, "#flash-error", "You can't do that on this character.")

      render_hook(lv, "edit_entry", %{"id" => entry.id})
      assert has_element?(lv, "#flash-error", "That item does not exist.")

      render_hook(lv, "delete_entry", %{"id" => entry.id})
      assert has_element?(lv, "#flash-error", "You can't do that on this character.")
      assert Diary.get_entry(ctx.character, entry.id)
    end

    test "muted owners cannot write", ctx do
      mute!(ctx, ctx.player)
      {:ok, lv, _} = live(conn_for(ctx.player), ctx.path)

      lv |> element("#diary-new-entry") |> render_click()

      lv
      |> form("#diary-form", entry: %{title: "Hi", body: "There", visibility: "public"})
      |> render_submit()

      assert has_element?(lv, "#flash-error", "You cannot write in this GDR right now.")
      assert Diary.list_entries(ctx.character, ctx.player) == []
    end
  end

  describe "guild page" do
    setup ctx do
      story = enable_modules(ctx.story, [:guilds])
      character = character_fixture(ctx.player, story)

      {:ok, police} =
        Guilds.create_guild(story, %{
          name: "Police",
          open_join: true,
          description: "**Sworn** to serve"
        })

      {:ok, cadet} = Guilds.create_rank(police, %{name: "Cadet", salary: 20, position: 0})

      {:ok, captain} =
        Guilds.create_rank(police, %{name: "Captain", salary: 80, position: 1, leader: true})

      {:ok, echo} =
        Guilds.create_guild(story, %{name: "Echo", secret: true, open_join: false})

      %{
        story: story,
        character: character,
        police: police,
        cadet: cadet,
        captain: captain,
        echo: echo,
        police_path: ~p"/g/#{story}/guilds/#{police}",
        echo_path: ~p"/g/#{story}/guilds/#{echo}"
      }
    end

    test "a leader manages the lower ranks and expels a member", ctx do
      {:ok, lead} =
        Guilds.enrol(ctx.master, ctx.story, ctx.police, ctx.character.id, ctx.captain.id)

      other_character = character_fixture(ctx.other, ctx.story)

      {:ok, member} =
        Guilds.enrol(ctx.master, ctx.story, ctx.police, other_character.id, ctx.cadet.id)

      {:ok, lv, _} = live(conn_for(ctx.player), ctx.police_path)
      assert has_element?(lv, "#guild-description strong", "Sworn")
      assert has_element?(lv, "#guild-management")
      refute has_element?(lv, "#enrol-form")
      refute has_element?(lv, "#rank-form-#{lead.id}")
      assert has_element?(lv, "#rank-form-#{member.id} option[value='#{ctx.cadet.id}']")
      refute has_element?(lv, "#rank-form-#{member.id} option[value='#{ctx.captain.id}']")

      lv |> element("#expel-#{member.id}") |> render_click()
      assert has_element?(lv, "#flash-info", "Member expelled.")
      refute has_element?(lv, "#member-#{member.id}")
      refute Guilds.membership_for(other_character, ctx.police)
    end

    test "requests are withdrawn by the player or rejected by a master", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ctx.police_path)
      lv |> element("#request-join") |> render_click()
      lv |> element("#cancel-request") |> render_click()
      assert has_element?(lv, "#flash-info", "Request withdrawn.")
      assert has_element?(lv, "#request-join")

      lv |> element("#request-join") |> render_click()
      [pending] = Guilds.list_pending(ctx.police)

      {:ok, mlv, _} = live(conn_for(ctx.master), ctx.police_path)
      mlv |> element("#reject-#{pending.id}") |> render_click()
      assert has_element?(mlv, "#flash-info", "Removed.")
      refute has_element?(mlv, "#pending-#{pending.id}")
      assert Guilds.list_pending(ctx.police) == []
    end

    test "a master invites and enrols characters", ctx do
      other_character = character_fixture(ctx.other, ctx.story)
      {:ok, lv, _} = live(conn_for(ctx.master), ctx.police_path)

      lv |> form("#invite-form", invite: %{character_id: ctx.character.id}) |> render_submit()
      assert has_element?(lv, "#flash-info", "Invitation sent.")

      lv
      |> form("#enrol-form", enrol: %{character_id: other_character.id, rank_id: ctx.cadet.id})
      |> render_submit()

      assert has_element?(lv, "#flash-info", "Character enrolled.")
      assert %{status: "active"} = Guilds.membership_for(other_character, ctx.police)
    end

    test "secret invitations hide the members; declining leaves the page", ctx do
      {:ok, _} = Guilds.invite(ctx.master, ctx.story, ctx.echo, ctx.character.id)

      {:ok, lv, _} = live(conn_for(ctx.player), ctx.echo_path)
      assert has_element?(lv, "#members-hidden")
      lv |> element("#decline-invitation") |> render_click()
      assert_redirect(lv, ~p"/g/#{ctx.story}/guilds")

      {:ok, _} = Guilds.invite(ctx.master, ctx.story, ctx.echo, ctx.character.id)
      {:ok, lv, _} = live(conn_for(ctx.player), ctx.echo_path)
      lv |> element("#accept-invitation") |> render_click()
      assert has_element?(lv, "#flash-info", "Welcome to the guild.")
      assert has_element?(lv, "#leave-guild")
      assert has_element?(lv, "#guild-members", ctx.character.name)
    end

    test "stale or forged actions fail gracefully", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ctx.police_path)
      render_hook(lv, "own", %{"op" => "cancel"})
      assert has_element?(lv, "#flash-error", "That membership does not exist.")

      lv |> element("#request-join") |> render_click()
      render_hook(lv, "own", %{"op" => "bogus"})
      assert has_element?(lv, "#flash-error", "That membership has changed in the meantime.")

      {:ok, mlv, _} = live(conn_for(ctx.master), ctx.police_path)
      render_hook(mlv, "approve", %{"id" => "0"})
      assert has_element?(mlv, "#flash-error", "That membership does not exist.")

      {:ok, lv, _} = live(conn_for(user_fixture()), ctx.police_path)
      refute has_element?(lv, "#request-join")
      render_hook(lv, "request", %{})
      assert has_element?(lv, "#flash-error", "That character can't join this guild.")
    end

    test "the page leaves when the guild is deleted meanwhile", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ctx.police_path)
      {:ok, _} = Guilds.delete_guild(ctx.police)

      render_hook(lv, "own", %{"op" => "cancel"})
      assert_redirect(lv, ~p"/g/#{ctx.story}/guilds")
    end
  end

  describe "notice boards" do
    setup ctx do
      story = enable_modules(ctx.story, [:boards, :reports])
      room = location_fixture(story, %{name: "Docks"})

      {:ok, board} =
        Boards.create_board(ctx.master, story, %{
          "name" => "Dock wall",
          "description" => "Public notices of the docks",
          "location_id" => room.id
        })

      %{story: story, board: board, character: character_fixture(ctx.player, story)}
    end

    test "masters manage, descriptions and expiries show", ctx do
      expires = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)

      {:ok, notice} =
        Boards.post_notice(ctx.player, ctx.story, ctx.board, %{
          "character_id" => ctx.character.id,
          "body" => "Lost cat",
          "expires_at" => expires
        })

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/boards")
      assert has_element?(lv, "#boards-manage")
      assert has_element?(lv, "#board-#{ctx.board.id}", "Public notices of the docks")
      assert has_element?(lv, "#notice-#{notice.id}", "until")
    end

    test "the notice form validates, cancels and rejects a blank notice", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/boards")
      refute has_element?(lv, "#boards-manage")
      form_id = "#notice-form-#{ctx.board.id}"

      lv |> element("#board-#{ctx.board.id}-post") |> render_click()
      lv |> form(form_id, notice: %{body: ""}) |> render_change()
      assert has_element?(lv, form_id)

      render_hook(lv, "cancel_notice", %{})
      refute has_element?(lv, form_id)

      lv |> element("#board-#{ctx.board.id}-post") |> render_click()
      lv |> form(form_id, notice: %{body: ""}) |> render_submit()
      assert has_element?(lv, form_id)
      assert has_element?(lv, "#board-#{ctx.board.id}-empty")
    end

    test "posting to a board taken down meanwhile fails", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/boards")
      lv |> element("#board-#{ctx.board.id}-post") |> render_click()

      {:ok, _} = Boards.delete_board(ctx.master, ctx.story, ctx.board)
      refute has_element?(lv, "#board-#{ctx.board.id}")

      render_hook(lv, "post_notice", %{"notice" => %{"body" => "Hello"}})

      assert has_element?(lv, "#flash-error", "That item does not exist in this GDR.")
    end

    test "other players' notices can be reported but not removed", ctx do
      other_character = character_fixture(ctx.other, ctx.story)

      {:ok, notice} =
        Boards.post_notice(ctx.other, ctx.story, ctx.board, %{
          "character_id" => other_character.id,
          "body" => "Selling stuff"
        })

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/boards")
      assert has_element?(lv, "#notice-report-#{notice.id}")
      refute has_element?(lv, "#notice-delete-#{notice.id}")

      render_hook(lv, "delete_notice", %{"id" => notice.id})
      assert has_element?(lv, "#flash-error", "You can't do that on this board.")

      render_hook(lv, "delete_notice", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", "That item does not exist in this GDR.")

      send(lv.pid, :unrelated)
      assert has_element?(lv, "#notice-#{notice.id}")
      assert Boards.get_notice(ctx.story, notice.id)
    end
  end

  describe "esiti" do
    setup ctx do
      story = enable_modules(ctx.story, [:esiti, :items])
      room = location_fixture(story, %{name: "Warehouse"})
      character = character_fixture(ctx.player, story)
      ally = character_fixture(ctx.other, story, %{"name" => "Ally Vance"})

      %{story: story, room: room, character: character, ally: ally}
    end

    test "masters claim, release and dismiss a request", ctx do
      esito = file!(ctx)
      {:ok, lv, _} = live(conn_for(ctx.master), show_path(ctx, esito))

      lv |> element("#claim-esito") |> render_click()
      assert has_element?(lv, "#flash-info", "You took this request.")
      assert has_element?(lv, "#release-esito")

      lv |> element("#release-esito") |> render_click()
      assert has_element?(lv, "#flash-info", "Request back in the queue.")
      assert has_element?(lv, "#claim-esito")

      lv |> element("#dismiss-esito") |> render_click()
      assert has_element?(lv, "#flash-info", "Request dismissed.")
      assert has_element?(lv, "#esito-closed")
      refute has_element?(lv, "#esito-resolve")
    end

    test "blank messages and outcomes are rejected", ctx do
      esito = file!(ctx)
      {:ok, lv, _} = live(conn_for(ctx.master), show_path(ctx, esito))

      lv |> form("#esito-message-form", message: %{body: ""}) |> render_submit()
      assert has_element?(lv, "#esito-message-form")
      assert Esiti.list_messages(esito) == []

      lv |> form("#esito-resolve-form", resolution: %{outcome: ""}) |> render_submit()
      assert has_element?(lv, "#flash-error")
      assert has_element?(lv, "#esito-status", "Open")

      # Another request filed meanwhile doesn't touch this page.
      file!(ctx, %{"title" => "Second"})
      assert has_element?(lv, "#esito-title", "Night at the warehouse")
    end

    test "a player cannot write on a closed request", ctx do
      esito = file!(ctx)
      {:ok, lv, _} = live(conn_for(ctx.player), show_path(ctx, esito))

      {:ok, _} = Esiti.dismiss(ctx.master, ctx.story, esito)
      refute has_element?(lv, "#esito-message-form")

      render_hook(lv, "post", %{"message" => %{"body" => "Wait!"}})
      assert has_element?(lv, "#flash-error")
      assert Esiti.list_messages(esito) == []
    end

    test "the request shows its place, date and companions; the resolve form every effect",
         ctx do
      sheet_item_fixture(ctx.story)
      {:ok, _} = Items.create_item(ctx.story, %{"name" => "Crowbar", "price" => 5})

      tracker =
        tracker_fixture(ctx.story, %{
          "name" => "Health",
          "slug" => "health",
          "max_formula" => "10",
          "damage_types" => "light, deep"
        })

      esito =
        file!(ctx, %{"location_id" => ctx.room.id, "related_ids" => [to_string(ctx.ally.id)]})

      esito |> Ecto.Changeset.change(game_date_label: "3rd night of rain") |> Repo.update!()

      {:ok, lv, _} = live(conn_for(ctx.master), show_path(ctx, esito))
      assert has_element?(lv, "#esito-related", "Ally Vance")
      assert has_element?(lv, "#esito-game-date", "3rd night of rain")
      assert render(lv) =~ "Warehouse"
      assert has_element?(lv, "select[name='resolution[item_id]']")
      assert has_element?(lv, "select[name='resolution[tracker]']")
      assert has_element?(lv, "input[name='resolution[also_related]']")
      refute has_element?(lv, "select[name='resolution[tracker_damage_type]']")

      lv
      |> form("#esito-resolve-form",
        resolution: %{outcome: "Hurt.", roll: "true", tracker: tracker.slug}
      )
      |> render_change()

      assert has_element?(lv, "select[name='resolution[dice][items][]']")
      assert has_element?(lv, "select[name='resolution[tracker_damage_type]'] option", "deep")
    end

    test "the index validates, rejects blank requests and offers companions", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/esiti")
      refute has_element?(lv, "#esiti-master-queue")
      assert has_element?(lv, "select[name='esito[related_ids][]'] option", "Ally Vance")

      lv |> form("#esito-form", esito: %{title: "Draft"}) |> render_change()
      assert has_element?(lv, "#esito-form input[value='Draft']")

      lv
      |> form("#esito-form", esito: %{character_id: ctx.character.id, title: "", body: ""})
      |> render_submit()

      assert has_element?(lv, "#esito-form")
      assert Esiti.list_user_esiti(ctx.player, ctx.story) == []
    end

    test "the index updates live with the place and the handling master", ctx do
      esito = file!(ctx, %{"location_id" => ctx.room.id})
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/esiti")
      assert has_element?(lv, "#my-esiti", "Warehouse")

      {:ok, _} = Esiti.claim(ctx.master, ctx.story, esito)
      assert has_element?(lv, "#my-esiti", "handled by #{ctx.master.username}")

      # Someone else's request doesn't reload the list.
      {:ok, _} =
        Esiti.create_esito(ctx.other, ctx.story, %{
          "character_id" => to_string(ctx.ally.id),
          "title" => "Elsewhere",
          "body" => "Not mine."
        })

      refute has_element?(lv, "#my-esiti", "Elsewhere")
    end

    test "users without characters, no limits and the masters' queue link", ctx do
      {:ok, _} = Stories.update_story_as_gm(ctx.story, %{"esiti_max_open" => ""})

      {:ok, lv, _} = live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/esiti")
      assert has_element?(lv, "#esiti-no-characters")
      refute has_element?(lv, "#esito-form")
      refute has_element?(lv, "#esiti-limits")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/esiti")
      assert has_element?(lv, "#esiti-master-queue")
    end
  end
end
