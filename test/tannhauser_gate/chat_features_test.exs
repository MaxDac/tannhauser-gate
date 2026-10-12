defmodule TannhauserGate.ChatFeaturesTest do
  use TannhauserGate.DataCase, async: true

  import Ecto.Query
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bookings, Chat, Dice, Repo, Stories, Trackers}
  alias TannhauserGate.Chat.{ArchivedMessage, Message}
  alias TannhauserGate.Dice.Config

  # A deterministic die: returns the given values in order.
  defp dice(values) do
    key = make_ref()
    Process.put(key, values)

    fn _sides ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end

  defp pool_config(attrs \\ %{}) do
    struct(
      %Config{
        system: "pool",
        die_size: 10,
        success_threshold: 6,
        crit_rule: "pairs",
        crit_bonus: 2,
        special_tracker: "hunger",
        messy_crit: true,
        bestial_failure: true
      },
      attrs
    )
  end

  setup do
    {story, gm} = gdr_fixture()
    dexterity = sheet_item_fixture(story, %{name: "Dexterity"})
    tracker_fixture(story, %{"name" => "Hunger", "max_formula" => "5"})
    tracker_fixture(story, %{"name" => "Willpower", "max_formula" => "3"})
    player = user_fixture()

    character =
      character_fixture(player, story, %{"traits" => %{to_string(dexterity.id) => "3"}})

    {:ok, _} = Trackers.set(character, "hunger", 2)
    %{story: story, gm: gm, player: player, character: character}
  end

  describe "dice expressions" do
    test "parse terms and reject malformed input" do
      assert {:ok, [{:dice, 1, 2, 6}, {:dice, 1, 1, 4}, {:constant, -1}]} =
               Dice.parse_expression("2d6 + d4 - 1")

      assert {:error, _} = Dice.parse_expression("abc")
      assert {:error, _} = Dice.parse_expression("5")
      assert {:error, _} = Dice.parse_expression("100d6")
      assert {:error, _} = Dice.parse_expression("")
    end

    test "roll sums dice, items, constants and the modifier", %{character: character} do
      config = %Config{system: "expression"}

      assert {:ok, result} =
               Dice.roll(
                 character,
                 %{"expression" => "2d6+1", "items" => ["dexterity"], "modifier" => "2"},
                 config: config,
                 rng: dice([3, 4])
               )

      assert result["total"] == 3 + 4 + 1 + 3 + 2
      assert result["outcome"] == nil
      assert [%{"slug" => "dexterity", "value" => 3}] = result["items"]
      assert result["summary"] == "2d6+1 = 13"

      assert {:ok, %{"outcome" => "failure"}} =
               Dice.roll(character, %{"expression" => "1d6", "difficulty" => 7},
                 config: config,
                 rng: dice([6])
               )
    end

    test "unknown sheet items are rejected", %{character: character} do
      assert {:error, :unknown_item} =
               Dice.roll(character, %{"items" => ["nope"]}, config: %Config{})
    end
  end

  describe "d20" do
    test "natural criticals and difficulty", %{character: character} do
      config = %Config{system: "d20"}
      request = %{"items" => ["dexterity"], "modifier" => 1, "difficulty" => 15}

      assert {:ok, %{"outcome" => "critical"}} =
               Dice.roll(character, request, config: config, rng: dice([20]))

      assert {:ok, %{"outcome" => "critical_failure"}} =
               Dice.roll(character, request, config: config, rng: dice([1]))

      assert {:ok, %{"total" => 16, "outcome" => "success"}} =
               Dice.roll(character, request, config: config, rng: dice([12]))

      assert {:ok, %{"outcome" => "failure"}} =
               Dice.roll(character, request,
                 config: %{config | natural_crits: false},
                 rng: dice([10])
               )
    end
  end

  describe "success pool" do
    test "pool size, special dice and messy criticals", %{character: character} do
      # 3 (dexterity) + 2 = 5 dice, the last 2 are special (hunger 2).
      assert {:ok, result} =
               Dice.roll(
                 character,
                 %{"items" => ["dexterity"], "modifier" => 2, "difficulty" => 4},
                 config: pool_config(),
                 rng: dice([10, 3, 6, 10, 1])
               )

      assert result["pool"] == 5
      assert result["special_count"] == 2
      assert Enum.map(result["dice"], & &1["special"]) == [false, false, false, true, true]
      assert result["crits"] == 1
      assert result["successes"] == 5
      assert result["margin"] == 1
      assert result["outcome"] == "messy_critical"
    end

    test "regular criticals and bestial failures", %{character: character} do
      request = %{"items" => ["dexterity"], "modifier" => 2}

      assert {:ok, %{"outcome" => "critical", "successes" => 5}} =
               Dice.roll(character, request, config: pool_config(), rng: dice([10, 10, 7, 1, 2]))

      assert {:ok, %{"outcome" => "bestial_failure", "successes" => 0}} =
               Dice.roll(character, request, config: pool_config(), rng: dice([2, 3, 4, 5, 1]))

      assert {:ok, %{"outcome" => "failure"}} =
               Dice.roll(character, request,
                 config: pool_config(%{bestial_failure: false}),
                 rng: dice([2, 3, 4, 5, 1])
               )

      assert {:ok, %{"outcome" => "critical"}} =
               Dice.roll(character, request,
                 config: pool_config(%{messy_crit: false}),
                 rng: dice([1, 1, 1, 10, 10])
               )
    end

    test "rerolls spend the tracker once", %{character: character} do
      config =
        pool_config(%{special_tracker: nil, reroll_tracker: "willpower", reroll_max_dice: 2})

      {:ok, result} =
        Dice.roll(character, %{"modifier" => 5}, config: config, rng: dice([2, 3, 7, 8, 1]))

      assert result["successes"] == 2
      assert Dice.rerollable?(config, result)
      refute Dice.rerollable?(%{config | reroll_tracker: nil}, result)

      assert {:ok, rerolled} =
               Dice.reroll(character, result, nil, config: config, rng: dice([9, 6]))

      assert rerolled["rerolled_indexes"] == [0, 1]
      assert rerolled["successes"] == 4
      assert rerolled["reroll_tracker"] == "Willpower"
      assert Trackers.get(character, "willpower").value == 2

      assert {:error, :already_rerolled} = Dice.reroll(character, rerolled, nil, config: config)
      assert {:error, :invalid_dice} = Dice.reroll(character, result, [2], config: config)

      {:ok, _} = Trackers.set(character, "willpower", 0)
      assert {:error, :not_enough} = Dice.reroll(character, result, nil, config: config)
    end
  end

  describe "chat entry types" do
    setup %{story: story} do
      %{location: location_fixture(story)}
    end

    test "OFF is allowed to draft owners, in character requires can_play?", ctx do
      drafter = user_fixture()
      draft = draft_character_fixture(drafter, ctx.story)

      assert {:error, :cannot_play} =
               Chat.create_message(drafter, ctx.location, %{
                 "character_id" => draft.id,
                 "body" => "In character"
               })

      assert {:ok, %Message{kind: "ooc"}} =
               Chat.create_message(drafter, ctx.location, %{
                 "character_id" => draft.id,
                 "body" => "brb",
                 "kind" => "ooc"
               })

      assert {:error, :invalid_kind} =
               Chat.create_message(ctx.player, ctx.location, %{
                 "character_id" => ctx.character.id,
                 "body" => "x",
                 "kind" => "narration"
               })

      assert {:error, :unauthorized} =
               Chat.create_message(user_fixture(), ctx.location, %{
                 "character_id" => draft.id,
                 "body" => "x",
                 "kind" => "ooc"
               })
    end

    test "narration and room status are for masters", ctx do
      assert {:error, :not_master} = Chat.narrate(ctx.player, ctx.location, "Thunder.")
      assert {:ok, message} = Chat.narrate(ctx.gm, ctx.location, "Thunder.")
      assert message.kind == "narration"
      assert message.character_id == nil
      assert Chat.speaker_name(message) == Chat.narrator()

      assert {:error, :not_master} = Chat.set_room_status(ctx.player, ctx.location, "Dark")

      assert {:ok, location, status} =
               Chat.set_room_status(ctx.gm, ctx.location, "The power is out.")

      assert location.status == "The power is out."
      assert status.kind == "status"
      assert Stories.get_location!(location.id).status == "The power is out."

      assert {:ok, location, _} = Chat.set_room_status(ctx.gm, location, " ")
      assert location.status == nil
    end

    test "dice entries store the structured result", ctx do
      {:ok, _} =
        Stories.update_story(ctx.story, %{
          "dice_config" => %{"system" => "d20", "natural_crits" => "false"}
        })

      assert {:ok, message} =
               Chat.roll_dice(
                 ctx.player,
                 ctx.location,
                 %{
                   "character_id" => ctx.character.id,
                   "items" => ["dexterity"],
                   "label" => "Shoot"
                 },
                 rng: dice([11])
               )

      assert message.kind == "dice"
      assert message.data["total"] == 14
      assert message.body == "Shoot: d20 (11) = 14"

      drafter = user_fixture()
      draft = draft_character_fixture(drafter, ctx.story)

      assert {:error, :cannot_play} =
               Chat.roll_dice(drafter, ctx.location, %{"character_id" => draft.id})

      npc = npc_fixture(ctx.gm, ctx.story)
      assert {:ok, _} = Chat.roll_dice(ctx.gm, ctx.location, %{"character_id" => npc.id})

      assert {:error, :unauthorized} =
               Chat.roll_dice(ctx.player, ctx.location, %{"character_id" => npc.id})
    end

    test "rerolls via the chat are for the roller and masters", ctx do
      {:ok, _} =
        Stories.update_story(ctx.story, %{
          "dice_config" => %{
            "system" => "pool",
            "reroll_tracker" => "willpower",
            "reroll_max_dice" => "1"
          }
        })

      {:ok, message} =
        Chat.roll_dice(ctx.player, ctx.location, %{"character_id" => ctx.character.id},
          rng: dice([2, 2, 2])
        )

      assert message.data["pool"] == 1

      assert {:error, :unauthorized} = Chat.reroll(user_fixture(), message)
      assert {:ok, updated} = Chat.reroll(ctx.gm, message, nil, rng: dice([8]))
      assert updated.data["rerolled"]
      assert updated.data["successes"] == 1
      assert {:error, :already_rerolled} = Chat.reroll(ctx.player, updated)
    end
  end

  describe "history" do
    setup %{story: story} do
      %{location: location_fixture(story)}
    end

    defp backdate(message, days) do
      at = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)
      Repo.update_all(from(m in Message, where: m.id == ^message.id), set: [inserted_at: at])
    end

    test "page_messages pages back to older entries", ctx do
      [m1, m2, m3] =
        for body <- ~w(one two three),
            do: message_fixture(ctx.player, ctx.location, ctx.character, body)

      backdate(m1, 3)
      backdate(m2, 2)
      backdate(m3, 1)

      assert {[%{body: "two"}, %{body: "three"} = _], true} =
               Chat.page_messages(ctx.location.id, limit: 2)

      oldest = Chat.get_message!(m2.id)

      assert {[%{body: "one"}], false} =
               Chat.page_messages(ctx.location.id, limit: 2, before: oldest)
    end

    test "old messages are archived per GDR and stay in the chat log", ctx do
      old = message_fixture(ctx.player, ctx.location, ctx.character, "Ancient words")
      backdate(old, 40)
      _recent = message_fixture(ctx.player, ctx.location, ctx.character, "Fresh words")

      {other_story, other_gm} = gdr_fixture(%{archive_after_days: nil})
      other_location = location_fixture(other_story)
      {:ok, kept} = Chat.narrate(other_gm, other_location, "Kept forever")
      backdate(kept, 400)

      assert Chat.archive_old_messages() == 1
      refute Repo.get(Message, old.id)
      assert Repo.get(Message, kept.id)

      assert [%ArchivedMessage{speaker_name: speaker}] =
               Repo.all(ArchivedMessage) |> Enum.filter(&(&1.location_id == ctx.location.id))

      assert speaker == ctx.character.name

      log = Chat.search_log(ctx.story.id)

      assert [%{body: "Fresh words", archived?: false}, %{body: "Ancient words", archived?: true}] =
               log

      today = Date.utc_today() |> Date.to_iso8601()
      assert [%{body: "Fresh words"}] = Chat.search_log(ctx.story.id, %{"from" => today})

      assert [%{body: "Ancient words"}] =
               Chat.search_log(ctx.story.id, %{
                 "to" => Date.utc_today() |> Date.add(-30) |> Date.to_iso8601(),
                 "location_id" => to_string(ctx.location.id)
               })

      assert [] = Chat.search_log(ctx.story.id, %{"location_id" => "-1"})
    end
  end

  describe "private rooms" do
    setup %{story: story} do
      %{location: location_fixture(story, %{private: true}), public: location_fixture(story)}
    end

    defp iso(now, hours), do: now |> DateTime.add(hours, :hour) |> DateTime.to_iso8601()

    test "bookings: slots, overlaps and access", ctx do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      friend = user_fixture()
      friend_character = character_fixture(friend, ctx.story)
      stranger = user_fixture()

      attrs = %{
        "character_id" => ctx.character.id,
        "starts_at" => iso(now, -1),
        "ends_at" => iso(now, 1),
        "invitee_ids" => [to_string(friend_character.id)]
      }

      assert {:error, :not_private} = Bookings.create_booking(ctx.player, ctx.public, attrs, now)

      # A start in the past is fine as long as the end is in the future.
      assert {:ok, booking} = Bookings.create_booking(ctx.player, ctx.location, attrs, now)
      assert [%{id: id}] = booking.invited_characters
      assert id == friend_character.id

      assert {:error, :overlap} =
               Bookings.create_booking(
                 friend,
                 ctx.location,
                 %{attrs | "character_id" => friend_character.id, "invitee_ids" => []},
                 now
               )

      assert Bookings.can_access?(ctx.player, ctx.location)
      assert Bookings.can_access?(friend, ctx.location)
      assert Bookings.can_access?(ctx.gm, ctx.location)
      refute Bookings.can_access?(stranger, ctx.location)
      refute Bookings.can_access?(ctx.player, ctx.location, DateTime.add(now, 2, :hour))
      assert Bookings.can_access?(stranger, ctx.public)

      stranger_character = character_fixture(stranger, ctx.story)

      assert {:error, :private} =
               Chat.create_message(stranger, ctx.location, %{
                 "character_id" => stranger_character.id,
                 "body" => "Let me in",
                 "kind" => "ooc"
               })

      assert {:ok, _} =
               Chat.create_message(friend, ctx.location, %{
                 "character_id" => friend_character.id,
                 "body" => "Thanks for the invite"
               })

      assert {:error, :unauthorized} = Bookings.cancel_booking(friend, booking)
      assert {:ok, _} = Bookings.cancel_booking(ctx.gm, booking)
      refute Bookings.can_access?(ctx.player, ctx.location)
    end

    test "booking validation", ctx do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      base = %{"character_id" => ctx.character.id, "invitee_ids" => []}

      assert {:error, %Ecto.Changeset{}} =
               Bookings.create_booking(
                 ctx.player,
                 ctx.location,
                 Map.merge(base, %{"starts_at" => iso(now, 2), "ends_at" => iso(now, 1)}),
                 now
               )

      assert {:error, %Ecto.Changeset{}} =
               Bookings.create_booking(
                 ctx.player,
                 ctx.location,
                 Map.merge(base, %{"starts_at" => iso(now, 1), "ends_at" => iso(now, 20)}),
                 now
               )

      drafter = user_fixture()
      draft = draft_character_fixture(drafter, ctx.story)

      assert {:error, :cannot_play} =
               Bookings.create_booking(
                 drafter,
                 ctx.location,
                 %{base | "character_id" => draft.id}
                 |> Map.merge(%{"starts_at" => iso(now, 1), "ends_at" => iso(now, 2)}),
                 now
               )

      {other_story, _} = gdr_fixture()
      outsider = character_fixture(nil, other_story)

      assert {:error, :invalid_invitee} =
               Bookings.create_booking(
                 ctx.player,
                 ctx.location,
                 Map.merge(base, %{
                   "starts_at" => iso(now, 1),
                   "ends_at" => iso(now, 2),
                   "invitee_ids" => [outsider.id]
                 }),
                 now
               )

      # datetime-local values as sent by the browser form (normalized to UTC).
      assert {:ok, booking} =
               Bookings.create_booking(
                 ctx.player,
                 ctx.location,
                 Map.merge(base, %{
                   "starts_at" =>
                     now |> DateTime.add(3, :hour) |> Calendar.strftime("%Y-%m-%dT%H:%M:00Z"),
                   "ends_at" =>
                     now |> DateTime.add(4, :hour) |> Calendar.strftime("%Y-%m-%dT%H:%M:00Z")
                 }),
                 now
               )

      assert booking.starts_at.second == 0
      assert [%{id: id}] = Bookings.list_upcoming(ctx.location)
      assert id == booking.id
      assert %{} = upcoming = Bookings.upcoming_by_location(ctx.story.id)
      assert [_] = upcoming[ctx.location.id]
    end
  end
end
