defmodule TannhauserGateWeb.MasterPagesLiveTest do
  @moduledoc """
  Edit, validation and error flows of the master tools sub-pages (guilds,
  quests, boards and weather).
  """
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Boards, Guilds, Items, Quests, Stories, Weather, Zones}

  setup do
    {story, _gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    %{story: story, master: master}
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp png_entry(name \\ "emblem.png"),
    do: %{name: name, content: png_fixture(), type: "image/png"}

  describe "guilds" do
    setup ctx do
      story = enable_modules(ctx.story, [:guilds])
      {:ok, guild} = Guilds.create_guild(story, %{name: "Police"})
      %{story: story, guild: guild}
    end

    test "guilds are validated, get an emblem, are edited and cancelled", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/guilds")

      lv |> form("#guild-form", guild: %{name: ""}) |> render_change()
      assert has_element?(lv, "#guild-form", "can't be blank")

      lv |> form("#guild-form", guild: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#guild-form", "can't be blank")

      lv |> element("#edit-guild-#{ctx.guild.id}") |> render_click()

      emblem = file_input(lv, "#guild-form", :emblem, [png_entry()])
      render_upload(emblem, "emblem.png")
      lv |> form("#guild-form", guild: %{name: "Police dept."}) |> render_submit()

      guild = Guilds.get_guild!(ctx.story, ctx.guild.id)
      assert guild.name == "Police dept."
      assert guild.emblem_path
      assert has_element?(lv, "#guild-emblem")
      assert has_element?(lv, "#master-guild-#{guild.id} img")

      lv |> element("#remove-guild-emblem") |> render_click()
      refute has_element?(lv, "#guild-emblem")
      assert Guilds.get_guild!(ctx.story, guild.id).emblem_path == nil

      lv |> element("#cancel-guild") |> render_click()
      refute has_element?(lv, "#cancel-guild")
    end

    test "pending emblems can be cancelled and bad files are rejected", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/guilds")

      emblem = file_input(lv, "#guild-form", :emblem, [png_entry()])
      render_upload(emblem, "emblem.png")
      lv |> element("#guild-form button[phx-click='cancel_upload']") |> render_click()
      refute has_element?(lv, "#guild-form button[phx-click='cancel_upload']")

      bad = file_input(lv, "#guild-form", :emblem, [%{name: "notes.txt", content: "hi"}])
      assert {:error, [[_ref, :not_accepted]]} = render_upload(bad, "notes.txt")

      render_click(lv, "remove_emblem", %{})
      assert has_element?(lv, "#guild-form")
    end

    test "unknown guilds and ranks show an error", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/guilds")

      render_click(lv, "edit", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Guilds.error_message(:guild_not_found))

      render_click(lv, "delete", %{"id" => "0"})
      assert [_] = Guilds.list_guilds(ctx.story)

      render_submit(lv, "save_rank", %{"rank" => %{"name" => "Chief"}})
      assert has_element?(lv, "#flash-error", Guilds.error_message(:guild_not_found))

      lv |> element("#edit-guild-#{ctx.guild.id}") |> render_click()
      render_click(lv, "edit_rank", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Guilds.error_message(:rank_not_found))

      render_click(lv, "delete_rank", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Guilds.error_message(:rank_not_found))
    end

    test "ranks are created, rejected, edited, cancelled and deleted", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/guilds")
      lv |> element("#edit-guild-#{ctx.guild.id}") |> render_click()
      assert has_element?(lv, "#guild-ranks")

      lv |> form("#rank-form", rank: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#rank-form", "can't be blank")

      lv
      |> form("#rank-form", rank: %{name: "Chief", salary: "10", leader: "true"})
      |> render_submit()

      [rank] = Guilds.get_guild!(ctx.story, ctx.guild.id).ranks
      assert has_element?(lv, "#rank-#{rank.id}", "leader")

      lv |> element("#edit-rank-#{rank.id}") |> render_click()
      lv |> form("#rank-form", rank: %{name: "Captain"}) |> render_submit()
      assert has_element?(lv, "#rank-#{rank.id}", "Captain")

      lv |> element("#edit-rank-#{rank.id}") |> render_click()
      lv |> element("#cancel-rank") |> render_click()
      refute has_element?(lv, "#cancel-rank")

      lv |> element("#delete-rank-#{rank.id}") |> render_click()
      refute has_element?(lv, "#rank-#{rank.id}")
      assert Guilds.get_guild!(ctx.story, ctx.guild.id).ranks == []
    end
  end

  describe "quests" do
    setup ctx do
      story = enable_modules(ctx.story, [:quests, :items])
      {:ok, item} = Items.create_item(story, %{name: "Medkit", price: 10})
      character = character_fixture(user_fixture(), story)

      {:ok, quest} =
        Quests.create_quest(ctx.master, story, %{
          "title" => "The blackout",
          "held_on" => "2026-10-01",
          "log_from" => "2026-10-01T20:00:00Z",
          "log_to" => "2026-10-01T23:00:00Z"
        })

      %{story: story, item: item, character: character, quest: quest}
    end

    test "quests are validated, edited, rejected and replaced by a new one", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/quests")

      lv |> form("#quest-form", quest: %{title: ""}) |> render_change()
      assert has_element?(lv, "#quest-form", "can't be blank")

      lv |> element("#edit-quest-#{ctx.quest.id}") |> render_click()
      assert has_element?(lv, "#quest_log_from[value='2026-10-01T20:00']")

      lv
      |> form("#quest-form", quest: %{log_from: "2026-10-02T10:00", log_to: "2026-10-02T09:00"})
      |> render_submit()

      assert has_element?(lv, "#quest-form", "must be after the start")

      lv
      |> form("#quest-form", quest: %{title: "The long night", log_to: "2026-10-02T11:00"})
      |> render_submit()

      assert Quests.get_quest(ctx.story, ctx.quest.id).title == "The long night"

      lv |> element("#new-quest") |> render_click()
      refute has_element?(lv, "#new-quest")

      render_click(lv, "edit", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Quests.error_message(:quest_not_found))

      render_click(lv, "delete", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Quests.error_message(:quest_not_found))
    end

    test "deleting the quest being edited resets the form", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/quests")
      lv |> element("#edit-quest-#{ctx.quest.id}") |> render_click()
      assert has_element?(lv, "#new-quest")

      lv |> element("#delete-quest-#{ctx.quest.id}") |> render_click()
      refute has_element?(lv, "#master-quest-#{ctx.quest.id}")
      refute has_element?(lv, "#new-quest")
    end

    test "participants get item rewards, are edited, cancelled and removed", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/quests")
      lv |> element("#edit-quest-#{ctx.quest.id}") |> render_click()
      assert has_element?(lv, "#participant_item_id")

      lv
      |> form("#participant-form", participant: %{character_id: ctx.character.id})
      |> render_submit()

      [p] = Quests.get_quest(ctx.story, ctx.quest.id).participants
      assert has_element?(lv, "#participant-#{p.id}", "no rewards")

      lv |> element("#edit-participant-#{p.id}") |> render_click()
      assert has_element?(lv, "#participant-form", ctx.character.name)
      assert has_element?(lv, "#participant_item_quantity")

      lv
      |> form("#participant-form", participant: %{item_id: ctx.item.id, item_quantity: "0"})
      |> render_submit()

      assert has_element?(lv, "#participant-form", "must be at least 1 for the item")

      lv
      |> form("#participant-form",
        participant: %{xp: "5", item_id: ctx.item.id, item_quantity: "2"}
      )
      |> render_submit()

      assert has_element?(lv, "#participant-#{p.id}", "Medkit × 2")

      lv |> element("#edit-participant-#{p.id}") |> render_click()
      lv |> element("#cancel-participant") |> render_click()
      refute has_element?(lv, "#cancel-participant")

      render_click(lv, "edit_participant", %{"id" => "0"})
      refute has_element?(lv, "#cancel-participant")

      lv |> element("#remove-participant-#{p.id}") |> render_click()
      refute has_element?(lv, "#participant-#{p.id}")
    end

    test "a master who lost the permission is refused", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/quests")
      lv |> element("#edit-quest-#{ctx.quest.id}") |> render_click()

      {:ok, p} =
        Quests.add_participant(ctx.master, ctx.story, ctx.quest, %{
          "character_id" => to_string(ctx.character.id)
        })

      {:ok, _} =
        Stories.set_master_permission(
          ctx.story,
          ctx.master.id,
          :can_manage_esiti_quests,
          false
        )

      message = Quests.error_message(:unauthorized)

      lv |> form("#quest-form", quest: %{title: "Nope"}) |> render_submit()
      assert has_element?(lv, "#flash-error", message)

      render_submit(lv, "save_participant", %{"participant" => %{"xp" => "1"}})
      assert has_element?(lv, "#flash-error", message)

      render_click(lv, "remove_participant", %{"id" => to_string(p.id)})
      assert has_element?(lv, "#flash-error", message)

      render_click(lv, "apply_rewards", %{})
      assert has_element?(lv, "#flash-error", message)

      render_click(lv, "delete", %{"id" => to_string(ctx.quest.id)})
      assert has_element?(lv, "#flash-error", message)
      assert Quests.get_quest(ctx.story, ctx.quest.id)
    end

    test "rewarding a quest deleted meanwhile resets the form", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/quests")
      lv |> element("#edit-quest-#{ctx.quest.id}") |> render_click()

      {:ok, _} = Quests.delete_quest(ctx.master, ctx.story, ctx.quest)

      render_click(lv, "apply_rewards", %{})
      assert has_element?(lv, "#flash-error", Quests.error_message(:quest_not_found))
      refute has_element?(lv, "#new-quest")
    end
  end

  describe "boards" do
    setup ctx do
      story = enable_modules(ctx.story, [:boards])
      room = location_fixture(story, %{name: "Docks"})

      {:ok, announcement} =
        Boards.create_announcement(ctx.master, story, %{
          "title" => "Curfew",
          "body" => "Stay inside",
          "expires_at" => "2020-01-01T10:00:00Z"
        })

      {:ok, board} =
        Boards.create_board(ctx.master, story, %{"name" => "Dock wall", "location_id" => room.id})

      %{story: story, room: room, announcement: announcement, board: board}
    end

    test "announcements are validated, rejected, edited and reset", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/boards")
      assert has_element?(lv, "#master-announcement-#{ctx.announcement.id}", "expired")

      lv |> form("#announcement-form", announcement: %{title: ""}) |> render_change()
      assert has_element?(lv, "#announcement-form", "can't be blank")

      lv |> form("#announcement-form", announcement: %{title: ""}) |> render_submit()
      assert has_element?(lv, "#announcement-form", "can't be blank")

      lv |> element("#announcement-edit-#{ctx.announcement.id}") |> render_click()
      assert has_element?(lv, "#announcement-form button[phx-click='new_announcement']")
      lv |> element("#announcement-form button[phx-click='new_announcement']") |> render_click()
      refute has_element?(lv, "#announcement-form button[phx-click='new_announcement']")

      render_click(lv, "edit_announcement", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Boards.error_message(:not_found))

      render_click(lv, "delete_announcement", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Boards.error_message(:not_found))
    end

    test "boards are validated, rejected, edited and reset", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/boards")

      lv |> form("#board-form", board: %{name: ""}) |> render_change()
      assert has_element?(lv, "#board-form", "can't be blank")

      lv |> form("#board-form", board: %{name: ""}) |> render_submit()
      assert has_element?(lv, "#board-form", "can't be blank")

      lv |> element("#board-edit-#{ctx.board.id}") |> render_click()
      lv |> form("#board-form", board: %{name: "Harbour wall"}) |> render_submit()
      assert [%{name: "Harbour wall"}] = Boards.list_all_boards(ctx.story)

      lv |> element("#board-edit-#{ctx.board.id}") |> render_click()
      assert has_element?(lv, "#board-form button[phx-click='new_board']")
      lv |> element("#board-form button[phx-click='new_board']") |> render_click()
      refute has_element?(lv, "#board-form button[phx-click='new_board']")

      render_click(lv, "edit_board", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Boards.error_message(:not_found))

      render_click(lv, "delete_board", %{"id" => "0"})
      assert has_element?(lv, "#flash-error", Boards.error_message(:not_found))

      send(lv.pid, :unrelated)
      assert has_element?(lv, "#master-board-#{ctx.board.id}")
    end

    test "a master who lost the world permission is refused", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/boards")
      {:ok, _} = Stories.set_master_permission(ctx.story, ctx.master.id, :can_manage_world, false)
      message = Boards.error_message(:unauthorized)

      lv |> form("#announcement-form", announcement: %{title: "T", body: "B"}) |> render_submit()
      assert has_element?(lv, "#flash-error", message)

      render_click(lv, "delete_announcement", %{"id" => to_string(ctx.announcement.id)})
      assert has_element?(lv, "#flash-error", message)

      lv |> form("#board-form", board: %{name: "New wall"}) |> render_submit()
      assert has_element?(lv, "#flash-error", message)

      render_click(lv, "delete_board", %{"id" => to_string(ctx.board.id)})
      assert has_element?(lv, "#flash-error", message)
      assert [_] = Boards.list_all_boards(ctx.story)
    end
  end

  describe "weather" do
    setup ctx do
      story = enable_modules(ctx.story, [:weather])
      {:ok, zone} = Zones.create_zone(story, %{name: "Docks"})

      {:ok, fog} =
        Weather.create_condition(story, %{
          name: "Fog",
          icon: "hero-eye-slash",
          description: "Thick smog",
          weights: %{"default" => 0}
        })

      %{story: story, zone: zone, fog: fog}
    end

    test "picking a preset fills the form; invalid weather is rejected", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/weather")

      lv
      |> element("#zone-weather-form")
      |> render_change(%{
        "_target" => ["weather", "preset"],
        "weather" => %{"zone_id" => ctx.zone.id, "preset" => to_string(ctx.fog.id)}
      })

      assert has_element?(lv, "#weather_condition[value='Fog']")
      assert has_element?(lv, "#weather_description[value='Thick smog']")

      lv
      |> element("#zone-weather-form")
      |> render_change(%{
        "_target" => ["weather", "preset"],
        "weather" => %{"zone_id" => ctx.zone.id, "preset" => "0", "condition" => ""}
      })

      lv
      |> element("#zone-weather-form")
      |> render_change(%{
        "_target" => ["weather", "condition"],
        "weather" => %{"zone_id" => ctx.zone.id, "condition" => ""}
      })

      assert has_element?(lv, "#zone-weather-form", "can't be blank")

      lv
      |> element("#zone-weather-form")
      |> render_submit(%{"weather" => %{"zone_id" => ctx.zone.id, "condition" => ""}})

      assert has_element?(lv, "#zone-weather-form", "can't be blank")
      assert Weather.zone_weather(ctx.zone) == nil

      lv
      |> element("#zone-weather-form")
      |> render_submit(%{
        "weather" => %{
          "zone_id" => ctx.zone.id,
          "condition" => "Fog",
          "icon" => "hero-eye-slash",
          "description" => "Can't see a thing"
        }
      })

      assert has_element?(lv, "#master-weather-zone-#{ctx.zone.id}", "Can't see a thing")

      send(lv.pid, :unrelated)
      assert has_element?(lv, "#zone-weather-#{ctx.zone.id}")
    end

    test "rolling a zone with an empty table shows an error", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/weather")
      render_click(lv, "roll", %{"zone" => to_string(ctx.zone.id)})
      assert has_element?(lv, "#flash-error", "no condition for this season")
    end
  end
end
