defmodule TannhauserGateWeb.ChatFeaturesLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Ecto.Query, only: [where: 2]
  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bookings, Chat, Repo, Stories, Trackers}
  alias TannhauserGate.Chat.Message

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    player = user_fixture()
    character = character_fixture(player, story)

    %{
      story: story,
      gm: gm,
      master: master,
      player: player,
      character: character,
      location: location_fixture(story)
    }
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp fixed_dice(values) do
    key = make_ref()
    Process.put(key, values)

    fn _sides ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end

  describe "chat entry types" do
    test "players only get in character and OFF entries", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")

      assert has_element?(lv, "#message-form-0 option[value=ooc]")
      refute has_element?(lv, "#message-form-0 option[value=narration]")

      lv
      |> form("#message-form-0",
        message: %{character_id: ctx.character.id, kind: "ooc", body: "brb"}
      )
      |> render_submit()

      assert has_element?(lv, "#messages li.chat-ooc", "brb")
    end

    test "masters narrate and set the room status", ctx do
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")

      lv
      |> form("#message-form-0", message: %{kind: "narration", body: "Thunder rolls."})
      |> render_submit()

      assert has_element?(lv, "#messages li.chat-narration", "Thunder rolls.")
      assert has_element?(lv, "#messages li.chat-narration .chat-name", Chat.narrator())

      lv
      |> form("form[phx-submit=send]", message: %{kind: "status", body: "The power is out."})
      |> render_submit()

      assert has_element?(lv, "#room-status", "The power is out.")
      assert has_element?(lv, "#messages li.chat-status", "The power is out.")
      assert Stories.get_location!(ctx.location.id).status == "The power is out."

      lv |> element("#clear-status") |> render_click()
      refute has_element?(lv, "#room-status")
    end
  end

  describe "dice" do
    test "players roll with the GDR dice system", ctx do
      item = sheet_item_fixture(ctx.story, %{name: "Firearms"})

      {:ok, _} =
        Stories.update_story(ctx.story, %{
          "dice_config" => %{"system" => "expression", "default_expression" => "1d6"}
        })

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      assert has_element?(lv, "#dice-panel")
      assert has_element?(lv, "#dice-form-0 option[value=#{item.slug}]")

      lv
      |> form("#dice-form-0",
        dice: %{
          character_id: ctx.character.id,
          items: [item.slug],
          expression: "2d6",
          modifier: "1",
          label: "Shoot"
        }
      )
      |> render_submit()

      assert [%Message{kind: "dice", id: id, data: data}] = Chat.list_messages(ctx.location.id)
      assert data["expression"] == "2d6"
      assert has_element?(lv, "#messages li.chat-dice")
      assert has_element?(lv, "#dice-result-#{id} .dice-summary")
      assert has_element?(lv, "#messages li.chat-dice", "Shoot")
    end

    test "rerolls spend the reroll tracker", ctx do
      tracker_fixture(ctx.story, %{"name" => "Willpower", "max_formula" => "3"})

      {:ok, _} =
        Stories.update_story(ctx.story, %{
          "dice_config" => %{"system" => "pool", "reroll_tracker" => "willpower"}
        })

      {:ok, message} =
        Chat.roll_dice(
          ctx.player,
          ctx.location,
          %{"character_id" => ctx.character.id, "modifier" => "2"},
          rng: fixed_dice([1, 2])
        )

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      lv |> element("#reroll-#{message.id}") |> render_click()

      assert Chat.get_message!(message.id).data["rerolled"]
      refute has_element?(lv, "#reroll-#{message.id}")
      assert Trackers.get(ctx.character, "willpower").value == 2

      {:ok, lv, _} = live(conn_for(user_fixture()), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      refute has_element?(lv, "#reroll-#{message.id}")
    end

    test "players without a playable character cannot roll", ctx do
      drafter = user_fixture()
      draft_character_fixture(drafter, ctx.story)
      {:ok, lv, _} = live(conn_for(drafter), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      refute has_element?(lv, "#dice-panel")
    end
  end

  describe "history" do
    test "older messages load on demand, in order", ctx do
      for n <- 1..53, do: message_fixture(ctx.player, ctx.location, ctx.character, "msg #{n}")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      assert has_element?(lv, "#load-older")
      refute has_element?(lv, "#messages li.chat-message", "msg 3\n")

      html = lv |> element("#load-older") |> render_click()
      refute has_element?(lv, "#load-older")

      bodies =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#messages li.chat-message .chat-body")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert length(bodies) == 53
      assert bodies == Enum.map(1..53, &"msg #{&1}")
    end

    test "masters search live and archived messages", ctx do
      other = location_fixture(ctx.story)
      old = message_fixture(ctx.player, ctx.location, ctx.character, "Ancient words")
      at = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.truncate(:second)
      Repo.update_all(where(Message, id: ^old.id), set: [inserted_at: at])
      assert Chat.archive_old_messages() >= 1
      message_fixture(ctx.player, other, ctx.character, "Fresh words")

      assert {:error, {:redirect, _}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/master/chat-log")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/chat-log")
      assert has_element?(lv, "#chat-log li", "Ancient words")
      assert has_element?(lv, "#chat-log li .archived-badge")
      assert has_element?(lv, "#chat-log li", "Fresh words")

      lv
      |> form("#chat-log-filters", filters: %{location_id: other.id})
      |> render_submit()

      assert_patch(lv)
      assert has_element?(lv, "#chat-log li", "Fresh words")
      refute has_element?(lv, "#chat-log li", "Ancient words")
      assert has_element?(lv, "#chat-log-count", "1 entries")
    end
  end

  describe "presence" do
    test "the online list shows who is where", ctx do
      {:ok, _room, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")
      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}")

      assert has_element?(lv, "#online-user-#{ctx.player.id}", ctx.location.name)
      assert has_element?(lv, "#online-user-#{ctx.master.id}")
    end
  end

  describe "private rooms" do
    setup ctx do
      %{private: location_fixture(ctx.story, %{private: true})}
    end

    test "only participants and masters get in during a booking", ctx do
      stranger = user_fixture()
      character_fixture(stranger, ctx.story)

      {:ok, lv, _} = live(conn_for(stranger), ~p"/g/#{ctx.story}/rooms/#{ctx.private}")
      assert has_element?(lv, "#private-badge")
      assert has_element?(lv, "#private-locked")
      refute has_element?(lv, "#message-form-0")

      {:ok, lv, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/rooms/#{ctx.private}")
      refute has_element?(lv, "#private-locked")
      assert has_element?(lv, "#message-form-0")
    end

    test "players book a slot and get in", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{ctx.private}")
      assert has_element?(lv, "#private-locked")

      now = DateTime.utc_now()
      local = &Calendar.strftime(DateTime.add(now, &1, :minute), "%Y-%m-%dT%H:%M")

      lv
      |> form("#booking-form",
        booking: %{character_id: ctx.character.id, starts_at: local.(-1), ends_at: local.(60)}
      )
      |> render_submit()

      assert [booking] = Bookings.list_upcoming(ctx.private)
      assert has_element?(lv, "#booking-#{booking.id}")
      assert has_element?(lv, "#active-booking")
      refute has_element?(lv, "#private-locked")
      assert has_element?(lv, "#message-form-0")

      html =
        lv
        |> form("#booking-form",
          booking: %{character_id: ctx.character.id, starts_at: local.(10), ends_at: local.(20)}
        )
        |> render_submit()

      assert html =~ "overlaps"

      {:ok, map, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/map")
      assert has_element?(map, "#room-bookings-#{ctx.private.id}", ctx.character.name)

      lv |> element("#cancel-booking-#{booking.id}") |> render_click()
      assert Bookings.list_upcoming(ctx.private) == []
      assert has_element?(lv, "#private-locked")
    end
  end

  describe "GM configuration" do
    test "the GDR admin configures dice and the archive age", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/chat")

      lv
      |> form("#dice-config-form",
        story: %{
          archive_after_days: "7",
          dice_config: %{system: "pool", die_size: "6", success_threshold: "5"}
        }
      )
      |> render_submit()

      story = Stories.get_story!(ctx.story.id)
      assert story.archive_after_days == 7
      assert story.dice_config.system == "pool"
      assert story.dice_config.die_size == 6

      assert {:error, {:redirect, _}} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/gm/chat")
    end
  end
end
