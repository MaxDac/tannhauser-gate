defmodule TannhauserGate.ChatRpTest do
  use TannhauserGate.DataCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import Phoenix.Component, only: [sigil_H: 2]
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Chat, Experience, Repo, Stories}
  alias TannhauserGate.Chat.{ArchivedMessage, Message, Speech}
  alias TannhauserGate.Experience.Entry

  doctest TannhauserGate.Chat.Speech, import: true

  setup do
    {story, gm} = gdr_fixture()
    {:ok, master} = Stories.add_master(story, user_fixture().username)
    sender = user_fixture()
    receiver = user_fixture()
    stranger = user_fixture()

    %{
      story: story,
      gm: gm,
      master: master,
      sender: sender,
      receiver: receiver,
      stranger: stranger,
      from: character_fixture(sender, story),
      to: character_fixture(receiver, story),
      other: character_fixture(stranger, story),
      location: location_fixture(story)
    }
  end

  defp rp(ctx, attrs \\ %{}) do
    story = enable_modules(ctx.story, [:chat_rp])
    {:ok, story} = Stories.update_story(story, attrs)
    story
  end

  defp whisper(ctx, body \\ "Meet me at the docks.") do
    Chat.create_message(ctx.sender, ctx.location, %{
      "character_id" => ctx.from.id,
      "kind" => "whisper",
      "recipient_character_id" => ctx.to.id,
      "body" => body
    })
  end

  defp say(ctx, body, extra \\ %{}) do
    Chat.create_message(
      ctx.sender,
      ctx.location,
      Map.merge(%{"character_id" => ctx.from.id, "body" => body}, extra)
    )
  end

  describe "whispers" do
    test "are rejected when the module is off", ctx do
      assert {:error, :invalid_kind} = whisper(ctx)
      assert Repo.aggregate(Message, :count) == 0
    end

    test "need an approved recipient of the GDR other than the sender", ctx do
      rp(ctx)
      {other_story, _} = gdr_fixture()
      foreign = character_fixture(user_fixture(), other_story)
      draft = draft_character_fixture(user_fixture(), ctx.story)

      for id <- [nil, "", "nope", foreign.id, draft.id] do
        assert {:error, :no_recipient} =
                 Chat.create_message(ctx.sender, ctx.location, %{
                   "character_id" => ctx.from.id,
                   "kind" => "whisper",
                   "recipient_character_id" => id,
                   "body" => "psst"
                 })
      end

      assert {:error, :whisper_self} =
               Chat.create_message(ctx.sender, ctx.location, %{
                 "character_id" => ctx.from.id,
                 "kind" => "whisper",
                 "recipient_character_id" => ctx.from.id,
                 "body" => "psst"
               })
    end

    test "the sender must be able to play", ctx do
      rp(ctx)
      draft = draft_character_fixture(user_fixture(), ctx.story)

      assert {:error, :cannot_play} =
               Chat.create_message(Repo.preload(draft, :user).user, ctx.location, %{
                 "character_id" => draft.id,
                 "kind" => "whisper",
                 "recipient_character_id" => ctx.to.id,
                 "body" => "psst"
               })
    end

    test "masters whisper as NPCs", ctx do
      rp(ctx)
      npc = npc_fixture(ctx.master, ctx.story)

      assert {:ok, %Message{kind: "whisper", recipient_character_id: to_id}} =
               Chat.create_message(ctx.master, ctx.location, %{
                 "character_id" => npc.id,
                 "kind" => "whisper",
                 "recipient_character_id" => ctx.to.id,
                 "body" => "You owe me."
               })

      assert to_id == ctx.to.id
    end

    test "are listed only for the sender, the recipient's owner and masters", ctx do
      rp(ctx)
      {:ok, _} = say(ctx, "Public words")
      {:ok, %{id: id}} = whisper(ctx)

      ids = fn viewer ->
        ctx.location.id |> Chat.list_messages(viewer: viewer) |> Enum.map(& &1.id)
      end

      assert id in ids.(ctx.sender)
      assert id in ids.(ctx.receiver)
      assert id in ids.(:all)
      refute id in ids.(ctx.stranger)
      refute id in ids.(nil)
      assert length(ids.(ctx.stranger)) == 1

      {page, false} = Chat.page_messages(ctx.location.id, viewer: ctx.stranger)
      refute Enum.any?(page, &(&1.id == id))

      assert [%{recipient_character: %{id: to_id}}] =
               ctx.location.id
               |> Chat.list_messages(viewer: ctx.receiver)
               |> Enum.filter(&(&1.id == id))

      assert to_id == ctx.to.id
    end

    test "older pages keep the filter", ctx do
      rp(ctx)
      {:ok, %{id: id}} = whisper(ctx)
      for n <- 1..3, do: {:ok, _} = say(ctx, "Line #{n}")

      {[oldest | _], true} = Chat.page_messages(ctx.location.id, limit: 2, viewer: ctx.stranger)

      assert {[%{body: "Line 1"}], false} =
               Chat.page_messages(ctx.location.id, limit: 2, before: oldest, viewer: ctx.stranger)

      {[oldest | _], true} = Chat.page_messages(ctx.location.id, limit: 2, viewer: ctx.receiver)

      assert {[%{id: ^id}, %{body: "Line 1"}], false} =
               Chat.page_messages(ctx.location.id, limit: 2, before: oldest, viewer: ctx.receiver)
    end

    test "are broadcast only on the topics of who may read them", ctx do
      rp(ctx)
      Chat.subscribe(ctx.location.id)
      {:ok, %{id: id}} = whisper(ctx)
      refute_receive {:new_message, %{id: ^id}}

      parent = self()

      for {viewer, expected} <- [
            {ctx.sender, true},
            {ctx.receiver, true},
            {ctx.stranger, false},
            {:all, true}
          ] do
        pid =
          spawn_link(fn ->
            Chat.subscribe_whispers(ctx.location.id, viewer)
            send(parent, {:subscribed, self()})

            receive do
              {:new_message, message} -> send(parent, {:got, self(), message.id})
            after
              300 -> send(parent, {:nothing, self()})
            end
          end)

        assert_receive {:subscribed, ^pid}
        {:ok, %{id: new_id}} = whisper(ctx, "Again #{inspect(viewer)}")

        if expected,
          do: assert_receive({:got, ^pid, ^new_id}),
          else: assert_receive({:nothing, ^pid}, 1_000)
      end
    end

    test "visible?/2 mirrors the listing rules", ctx do
      rp(ctx)
      {:ok, message} = whisper(ctx)

      assert Chat.visible?(message, ctx.sender)
      assert Chat.visible?(message, ctx.receiver)
      assert Chat.visible?(message, :all)
      refute Chat.visible?(message, ctx.stranger)
      refute Chat.visible?(message, nil)
    end

    test "deleting one broadcasts only its id", ctx do
      rp(ctx)
      {:ok, message} = whisper(ctx)
      Chat.subscribe(ctx.location.id)
      {:ok, _} = Chat.delete_message(message)
      id = message.id
      assert_receive {:deleted_message, %Message{id: ^id, body: nil}}
    end

    test "the archive and the masters log keep the recipient and the tag", ctx do
      rp(ctx)

      {:ok, _} =
        Chat.create_message(ctx.sender, ctx.location, %{
          "character_id" => ctx.from.id,
          "kind" => "whisper",
          "recipient_character_id" => ctx.to.id,
          "tag" => "leaning close",
          "body" => "Old secret"
        })

      assert [%{kind: "whisper", recipient: name, tag: "leaning close", archived?: false}] =
               Chat.search_log(ctx.story.id)

      assert name == ctx.to.name

      assert 1 = Chat.archive_old_messages(DateTime.add(DateTime.utc_now(), 40, :day))

      assert %ArchivedMessage{tag: "leaning close", recipient_name: ^name} =
               Repo.one!(ArchivedMessage)

      assert [%{kind: "whisper", recipient: ^name, tag: "leaning close", archived?: true}] =
               Chat.search_log(ctx.story.id)
    end

    test "moderation lists them with their recipient", ctx do
      rp(ctx)
      {:ok, %{id: id}} = whisper(ctx)
      assert [%{id: ^id, recipient_character: %{id: _}}] = Chat.list_story_messages(ctx.story.id)
    end
  end

  describe "action tags and length limits" do
    test "the tag is stored only with the module on", ctx do
      assert {:ok, %{tag: nil}} = say(ctx, "No tags here", %{"tag" => "at the bar"})
      rp(ctx)
      assert {:ok, %{tag: "at the bar"}} = say(ctx, "At last", %{"tag" => "  at the bar "})
      assert {:ok, %{tag: nil}} = say(ctx, "Blank", %{"tag" => "  "})

      assert {:ok, %{tag: nil}} =
               say(ctx, "OFF", %{"kind" => "ooc", "tag" => "ignored for OFF"})

      assert {:error, %Ecto.Changeset{errors: [tag: _]}} =
               say(ctx, "Too long", %{"tag" => String.duplicate("x", 41)})
    end

    test "in-character entries respect the GDR limits", ctx do
      {:ok, _} = Stories.update_story(ctx.story, %{chat_min_length: 10, chat_max_length: 20})
      # Module off: no limits.
      assert {:ok, _} = say(ctx, "Hi")

      rp(ctx)
      assert {:error, %Ecto.Changeset{} = cs} = say(ctx, "Hi")
      assert "should be at least 10 character(s)" in errors_on(cs).body
      assert {:error, %Ecto.Changeset{} = cs} = say(ctx, String.duplicate("a", 21))
      assert "should be at most 20 character(s)" in errors_on(cs).body
      assert {:ok, _} = say(ctx, "Exactly fine")
      # OFF entries are not in character.
      assert {:ok, _} = say(ctx, "brb", %{"kind" => "ooc"})

      assert {:error, %Ecto.Changeset{}} =
               Chat.create_message(ctx.sender, ctx.location, %{
                 "character_id" => ctx.from.id,
                 "kind" => "whisper",
                 "recipient_character_id" => ctx.to.id,
                 "body" => "psst"
               })
    end

    test "the GM settings are validated", ctx do
      assert {:error, cs} =
               Stories.update_story_as_gm(ctx.story, %{chat_min_length: 50, chat_max_length: 10})

      assert "must be at least the minimum length" in errors_on(cs).chat_max_length

      assert {:error, cs} = Stories.update_story_as_gm(ctx.story, %{auto_xp_amount: 0})
      assert errors_on(cs).auto_xp_amount != []
    end
  end

  describe "speech highlighting" do
    test "splits quoted speech from action" do
      assert Speech.segments(~s(He nods. “Fine.” Then: "Go." «Now!» end)) == [
               {:action, "He nods. "},
               {:speech, "“Fine.”"},
               {:action, " Then: "},
               {:speech, ~s("Go.")},
               {:action, " "},
               {:speech, "«Now!»"},
               {:action, " end"}
             ]

      assert Speech.segments(~s("Only words")) == [{:speech, ~s("Only words")}]
      assert Speech.segments("No quotes") == [{:action, "No quotes"}]
      assert Speech.segments(~s(Open "quote)) == [{:action, ~s(Open "quote)}]
      assert Speech.segments("") == []
      assert Speech.segments(nil) == []
    end

    test "renders segments as escaped text" do
      assigns = %{body: ~s[<b>x</b> "<script>alert(1)</script>"], tag: "<i>bar</i>"}

      html =
        rendered_to_string(~H"""
        <TannhauserGateWeb.ChatComponents.chat_body body={@body} tag={@tag} highlight />
        """)

      refute html =~ "<script>"
      refute html =~ "<b>"
      refute html =~ "<i>"
      assert html =~ "&lt;script&gt;"
      assert html =~ "chat-speech"
      assert html =~ "chat-action"
      assert html =~ "[&lt;i&gt;bar&lt;/i&gt;]"

      plain =
        rendered_to_string(~H"""
        <TannhauserGateWeb.ChatComponents.chat_body body={@body} />
        """)

      refute plain =~ "chat-speech"
      assert plain =~ "&lt;b&gt;"
    end
  end

  describe "automatic XP" do
    setup ctx do
      story = enable_modules(ctx.story, [:auto_xp])

      {:ok, story} =
        Stories.update_story(story, %{
          auto_xp_amount: 2,
          auto_xp_min_length: 10,
          auto_xp_daily_cap: 5,
          auto_xp_cooldown_minutes: 10
        })

      %{story: story}
    end

    defp auto_entries(character) do
      Repo.all(from e in Entry, where: e.character_id == ^character.id and e.source == "auto")
    end

    test "awards XP for a long enough in-character speech", ctx do
      {:ok, _} = say(ctx, "Short")
      assert auto_entries(ctx.from) == []

      {:ok, _} = say(ctx, "Long enough words")

      assert [%Entry{amount: 2, reason: "Chat activity", kind: "award", author_id: nil}] =
               auto_entries(ctx.from)

      assert Experience.totals(ctx.from).available == 2
    end

    test "excludes OFF, whispers, dice, narration and NPCs", ctx do
      enable_modules(ctx.story, [:chat_rp])
      {:ok, _} = say(ctx, "Out of character long text", %{"kind" => "ooc"})
      {:ok, _} = whisper(ctx, "A long whispered secret")
      {:ok, _} = Chat.narrate(ctx.master, ctx.location, "Thunder over the long docks")

      {:ok, _} =
        Chat.roll_dice(ctx.sender, ctx.location, %{
          "character_id" => ctx.from.id,
          "expression" => "1d6",
          "label" => "A long dice label"
        })

      npc = npc_fixture(ctx.master, ctx.story)

      {:ok, _} =
        Chat.create_message(ctx.master, ctx.location, %{
          "character_id" => npc.id,
          "body" => "An NPC speaks at length"
        })

      assert Repo.aggregate(Entry, :count) == 0
      assert {:error, :npc} = Experience.award_chat_activity(ctx.story, npc, 100)
    end

    test "respects the cooldown and the daily cap", ctx do
      t0 = ~U[2121-03-01 10:00:00Z]
      award = &Experience.award_chat_activity(ctx.story, ctx.from, 50, now: &1)

      assert {:ok, %{amount: 2}} = award.(t0)
      assert {:error, :cooldown} = award.(DateTime.add(t0, 5, :minute))
      assert {:ok, %{amount: 2}} = award.(DateTime.add(t0, 11, :minute))
      # Only 1 XP left before the daily cap of 5.
      assert {:ok, %{amount: 1}} = award.(DateTime.add(t0, 22, :minute))
      assert {:error, :daily_cap} = award.(DateTime.add(t0, 33, :minute))
      # A new UTC day resets the cap.
      assert {:ok, %{amount: 2}} = award.(~U[2121-03-02 00:01:00Z])
      assert Experience.totals(ctx.from).earned == 7
    end

    test "does nothing with the module off or no amount", ctx do
      {:ok, off} = Stories.set_module_enabled(ctx.story, :auto_xp, false)
      assert {:error, :disabled} = Experience.award_chat_activity(off, ctx.from, 100)

      {:ok, no_amount} = Stories.update_story(ctx.story, %{auto_xp_amount: nil})
      assert {:error, :disabled} = Experience.award_chat_activity(no_amount, ctx.from, 100)
      assert {:error, :too_short} = Experience.award_chat_activity(ctx.story, ctx.from, 3)

      {:ok, _} = Stories.set_module_enabled(ctx.story, :auto_xp, false)
      {:ok, _} = say(ctx, "Long enough words")
      assert auto_entries(ctx.from) == []
    end

    test "the story XP log filters by source", ctx do
      {:ok, _} = Experience.award(ctx.gm, ctx.from, 3, "Great scene")
      {:ok, _} = Experience.award_chat_activity(ctx.story, ctx.from, 100)

      assert [%{source: "auto"}] = Experience.list_story_entries(ctx.story.id, source: "auto")
      assert [%{source: "manual"}] = Experience.list_story_entries(ctx.story.id, source: "manual")
      assert length(Experience.list_story_entries(ctx.story.id, source: "all")) == 2
    end
  end

  describe "presence status" do
    test "is saved per GDR and validated", ctx do
      assert Stories.presence_status(ctx.sender, ctx.story.id) == "available"
      assert {:ok, "busy"} = Stories.set_presence_status(ctx.sender, ctx.story.id, "busy")
      assert {:ok, "away"} = Stories.set_presence_status(ctx.sender, ctx.story.id, "away")
      assert Stories.presence_status(ctx.sender, ctx.story.id) == "away"

      assert {:error, :invalid_status} =
               Stories.set_presence_status(ctx.sender, ctx.story.id, "x")

      {other, _} = gdr_fixture()
      assert Stories.presence_status(ctx.sender, other.id) == "available"
    end
  end
end
