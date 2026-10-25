defmodule TannhauserGateWeb.ChatRpLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Chat, Experience, Repo, Stories}
  alias TannhauserGate.Chat.Message

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

  defp conn_for(user), do: log_in_user(build_conn(), user)
  defp room(ctx, user), do: live(conn_for(user), ~p"/g/#{ctx.story}/rooms/#{ctx.location}")

  defp whisper(ctx, body) do
    {:ok, message} =
      Chat.create_message(ctx.sender, ctx.location, %{
        "character_id" => ctx.from.id,
        "kind" => "whisper",
        "recipient_character_id" => ctx.to.id,
        "body" => body
      })

    message
  end

  describe "module disabled" do
    test "the whisper option is hidden and forged whispers are rejected", ctx do
      {:ok, lv, _} = room(ctx, ctx.sender)

      refute has_element?(lv, "#message-form-0 option[value=whisper]")
      refute has_element?(lv, "#message_tag")
      refute has_element?(lv, "#message-counter")

      render_hook(lv, "send", %{
        "message" => %{
          "character_id" => ctx.from.id,
          "kind" => "whisper",
          "recipient_character_id" => ctx.to.id,
          "body" => "Forged"
        }
      })

      assert render(lv) =~ "That kind of message does not exist."
      assert Repo.aggregate(Message, :count) == 0
    end

    test "quotes are not highlighted", ctx do
      {:ok, lv, _} = room(ctx, ctx.sender)

      lv
      |> form("#message-form-0", message: %{character_id: ctx.from.id, body: ~s(Nods. "Yes.")})
      |> render_submit()

      [message] = Chat.list_messages(ctx.location.id)
      assert has_element?(lv, "#message-#{message.id}-body")
      refute has_element?(lv, "#message-#{message.id}-body .chat-speech")
    end
  end

  describe "whispers" do
    setup ctx, do: %{story: enable_modules(ctx.story, [:chat_rp])}

    test "a player whispers from the composer", ctx do
      {:ok, lv, _} = room(ctx, ctx.sender)
      assert has_element?(lv, "#message-form-0 option[value=whisper]")
      refute has_element?(lv, "#message_recipient_character_id")

      lv
      |> form("#message-form-0", message: %{character_id: ctx.from.id, kind: "whisper"})
      |> render_change()

      assert has_element?(lv, "#message_recipient_character_id option[value='#{ctx.to.id}']")
      # One's own characters are not offered.
      refute has_element?(lv, "#message_recipient_character_id option[value='#{ctx.from.id}']")

      lv
      |> form("#message-form-0",
        message: %{
          character_id: ctx.from.id,
          kind: "whisper",
          recipient_character_id: ctx.to.id,
          body: "Only for you."
        }
      )
      |> render_submit()

      [message] = Chat.list_messages(ctx.location.id, viewer: :all)
      assert %{kind: "whisper"} = message
      assert has_element?(lv, "#messages li.chat-whisper", "Only for you.")
      assert has_element?(lv, "#message-#{message.id}-recipient", ctx.to.name)
    end

    test "live whispers reach only the sender, the recipient and masters", ctx do
      {:ok, sender_lv, _} = room(ctx, ctx.sender)
      {:ok, receiver_lv, _} = room(ctx, ctx.receiver)
      {:ok, stranger_lv, _} = room(ctx, ctx.stranger)
      {:ok, master_lv, _} = room(ctx, ctx.master)

      message = whisper(ctx, "The vault code is 2121.")
      selector = "#messages-#{message.id}"

      assert has_element?(sender_lv, selector)
      assert has_element?(receiver_lv, selector, "The vault code is 2121.")
      assert has_element?(master_lv, selector, "The vault code is 2121.")
      refute has_element?(stranger_lv, selector)
      refute render(stranger_lv) =~ "vault code"

      # Public speech still reaches everyone.
      {:ok, public} =
        Chat.create_message(ctx.sender, ctx.location, %{
          "character_id" => ctx.from.id,
          "body" => "Nice weather."
        })

      assert has_element?(stranger_lv, "#messages-#{public.id}")
    end

    test "the history hides other players' whispers", ctx do
      message = whisper(ctx, "Secret history")
      selector = "#messages-#{message.id}"

      {:ok, stranger_lv, _} = room(ctx, ctx.stranger)
      refute has_element?(stranger_lv, selector)

      {:ok, receiver_lv, _} = room(ctx, ctx.receiver)
      assert has_element?(receiver_lv, selector)

      {:ok, master_lv, _} = room(ctx, ctx.gm)
      assert has_element?(master_lv, selector)
    end

    test "older pages hide other players' whispers", ctx do
      message = whisper(ctx, "Buried secret")

      for n <- 1..50 do
        {:ok, _} =
          Chat.create_message(ctx.stranger, ctx.location, %{
            "character_id" => ctx.other.id,
            "body" => "Line #{n}"
          })
      end

      selector = "#messages-#{message.id}"

      {:ok, stranger_lv, _} = room(ctx, ctx.stranger)
      refute has_element?(stranger_lv, "#load-older")

      {:ok, receiver_lv, _} = room(ctx, ctx.receiver)
      refute has_element?(receiver_lv, selector)
      receiver_lv |> element("#load-older") |> render_click()
      assert has_element?(receiver_lv, selector)
    end

    test "masters see whispers in the chat log and moderation", ctx do
      message = whisper(ctx, "Logged whisper")

      {:ok, log, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/chat-log")
      assert has_element?(log, "#chat-log .whisper-recipient", ctx.to.name)

      {:ok, moderation, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/moderation")
      assert has_element?(moderation, "#moderation-whisper-#{message.id}", ctx.to.name)
    end
  end

  describe "tags, highlighting and limits" do
    setup ctx do
      story = enable_modules(ctx.story, [:chat_rp])
      {:ok, story} = Stories.update_story(story, %{chat_min_length: 10, chat_max_length: 100})
      %{story: story}
    end

    test "a tagged entry with highlighted speech", ctx do
      {:ok, lv, _} = room(ctx, ctx.sender)
      assert has_element?(lv, "#message-counter", "0 / 100")

      lv
      |> form("#message-form-0",
        message: %{
          character_id: ctx.from.id,
          tag: "at the bar",
          body: ~s(She smiles. "Rain again.")
        }
      )
      |> render_submit()

      [message] = Chat.list_messages(ctx.location.id)
      assert message.tag == "at the bar"
      assert has_element?(lv, "#message-#{message.id}-body .chat-tag", "[at the bar]")
      assert has_element?(lv, "#message-#{message.id}-body .chat-speech", ~s("Rain again."))
      assert has_element?(lv, "#message-#{message.id}-body .chat-action", "She smiles.")
    end

    test "the counter follows the text and limits are enforced", ctx do
      {:ok, lv, _} = room(ctx, ctx.sender)

      lv
      |> form("#message-form-0", message: %{character_id: ctx.from.id, body: "Hi"})
      |> render_change()

      assert has_element?(lv, "#message-counter.text-error", "2 / 100")

      lv
      |> form("#message-form-0", message: %{character_id: ctx.from.id, body: "Hi"})
      |> render_submit()

      assert has_element?(lv, "#message-form-0", "should be at least 10 character(s)")
      assert Chat.list_messages(ctx.location.id) == []
    end
  end

  describe "automatic XP" do
    test "a long speech awards XP, shown in the master XP log filter", ctx do
      story = enable_modules(ctx.story, [:auto_xp])
      {:ok, _} = Stories.update_story(story, %{auto_xp_amount: 1, auto_xp_min_length: 5})
      {:ok, _} = Experience.award(ctx.gm, ctx.to, 4, "Manual award")

      {:ok, lv, _} = room(ctx, ctx.sender)

      lv
      |> form("#message-form-0", message: %{character_id: ctx.from.id, body: "A long speech."})
      |> render_submit()

      assert Experience.totals(ctx.from).earned == 1

      {:ok, dash, _} = live(conn_for(ctx.master), ~p"/g/#{ctx.story}/master/characters")
      [auto] = Experience.list_story_entries(ctx.story.id, source: "auto")
      [manual] = Experience.list_story_entries(ctx.story.id, source: "manual")
      assert has_element?(dash, "#story-xp-#{auto.id}", "Auto")
      assert has_element?(dash, "#story-xp-#{manual.id}")

      dash |> form("#xp-log-filter", xp_log: %{source: "auto"}) |> render_change()
      assert has_element?(dash, "#story-xp-#{auto.id}")
      refute has_element?(dash, "#story-xp-#{manual.id}")

      dash |> form("#xp-log-filter", xp_log: %{source: "manual"}) |> render_change()
      refute has_element?(dash, "#story-xp-#{auto.id}")
      assert has_element?(dash, "#story-xp-#{manual.id}")
    end
  end

  describe "GM configuration" do
    test "the module settings appear only when enabled and are saved", ctx do
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/chat")
      refute has_element?(lv, "#chat-rp-settings")
      refute has_element?(lv, "#auto-xp-settings")

      enable_modules(ctx.story, [:chat_rp, :auto_xp])
      {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm/chat")

      lv
      |> form("#dice-config-form",
        story: %{
          chat_min_length: "20",
          chat_max_length: "1500",
          auto_xp_amount: "2",
          auto_xp_min_length: "250",
          auto_xp_daily_cap: "8",
          auto_xp_cooldown_minutes: "15"
        }
      )
      |> render_submit()

      assert %{
               chat_min_length: 20,
               chat_max_length: 1500,
               auto_xp_amount: 2,
               auto_xp_min_length: 250,
               auto_xp_daily_cap: 8,
               auto_xp_cooldown_minutes: 15
             } = Stories.get_story!(ctx.story.id)
    end
  end

  describe "presence status" do
    test "a player changes status, shown in the online list and quick links", ctx do
      {:ok, lv, _} = room(ctx, ctx.sender)
      dot = "#online-user-#{ctx.sender.id}-status"
      assert has_element?(lv, "#{dot}.presence-available")

      lv
      |> form("#presence-status-form", presence: %{status: "looking_for_play"})
      |> render_change()

      assert has_element?(lv, "#{dot}.presence-looking_for_play")
      assert has_element?(lv, "#online-user-#{ctx.sender.id}-links-status", "Looking for play")
      assert Stories.presence_status(ctx.sender, ctx.story.id) == "looking_for_play"

      # Other users see it, and it survives a new page.
      {:ok, other, _} = room(ctx, ctx.stranger)
      assert has_element?(other, "#{dot}.presence-looking_for_play")

      {:ok, again, _} = live(conn_for(ctx.sender), ~p"/g/#{ctx.story}/map")
      assert has_element?(again, "#presence-status option[selected][value=looking_for_play]")
    end
  end
end
