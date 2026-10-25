defmodule TannhauserGateWeb.MultiCharactersLiveTest do
  use TannhauserGateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bank, Characters, Guilds, Items, Repo, Stories}
  alias TannhauserGate.Chat.Message

  setup do
    {story, gm} = gdr_fixture()
    {:ok, story} = Stories.update_story_as_gm(story, %{"max_characters_per_user" => 2})
    player = user_fixture()
    first = character_fixture(player, story, %{"name" => "Deckard"})
    second = character_fixture(player, story, %{"name" => "Rachael"})
    {:ok, _} = Characters.set_active_character(player, first)

    %{
      story: story,
      gm: gm,
      player: player,
      first: first,
      second: second,
      stranger: character_fixture(user_fixture(), story, %{"name" => "Gaff"})
    }
  end

  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp switch(lv, character) do
    lv
    |> form("#active-character-form", active: %{character_id: character.id})
    |> render_change()
  end

  describe "creation" do
    test "the create button follows the limit", ctx do
      user = user_fixture()
      character_fixture(user, ctx.story)
      {:ok, lv, _} = live(conn_for(user), ~p"/g/#{ctx.story}/characters")
      assert has_element?(lv, "#new-character", "Create another character")
      assert has_element?(lv, "#my-character")

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters")
      refute has_element?(lv, "#new-character")
      assert has_element?(lv, "#my-character", "Playing as Deckard")
    end

    test "the wizard opens below the limit and redirects at the limit", ctx do
      user = user_fixture()
      character_fixture(user, ctx.story)
      assert {:ok, lv, _} = live(conn_for(user), ~p"/g/#{ctx.story}/characters/new")
      assert has_element?(lv, "#character-form")

      assert {:error, {:live_redirect, %{to: path, flash: flash}}} =
               live(conn_for(ctx.player), ~p"/g/#{ctx.story}/characters/new")

      assert path == "/g/#{ctx.story.id}/characters/#{ctx.first.id}/edit"
      assert flash["info"] =~ "maximum number of characters"
    end
  end

  describe "active character selector" do
    test "is shown only with two or more characters", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")
      assert has_element?(lv, "#active-character option[selected][value='#{ctx.first.id}']")

      {:ok, lv, _} = live(conn_for(ctx.stranger.user_id |> user()), ~p"/g/#{ctx.story}")
      refute has_element?(lv, "#active-character-form")
    end

    test "switches the character used by the bank and shown in presence", ctx do
      {:ok, _} = Bank.adjust(ctx.second, 70)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/bank")
      assert has_element?(lv, "#bank-character", "Deckard")
      assert has_element?(lv, "#online-user-#{ctx.player.id}-links", "Deckard")

      assert {:error, {:live_redirect, %{to: path}}} = switch(lv, ctx.second)
      assert path == "/g/#{ctx.story.id}/bank"
      assert Characters.active_character(ctx.player, ctx.story).id == ctx.second.id

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/bank")
      assert has_element?(lv, "#bank-character", "Rachael")
      assert has_element?(lv, "#balance", "70")
      assert has_element?(lv, "#online-user-#{ctx.player.id}-links", "Rachael")

      lv
      |> form("#transfer-form", transfer: %{to: ctx.stranger.id, amount: 20})
      |> render_submit()

      assert Characters.get_character!(ctx.stranger.id).balance == 20
      refute has_element?(lv, "#transfer_to option[value='#{ctx.first.id}']")
    end

    test "cannot pick someone else's character", ctx do
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}")

      render_change(lv, "set_active_character", %{
        "active" => %{"character_id" => to_string(ctx.stranger.id)}
      })

      assert Characters.active_character(ctx.player, ctx.story).id == ctx.first.id
    end
  end

  describe "acting as the character" do
    test "the chat defaults to the active character and speaks as either", ctx do
      location = location_fixture(ctx.story)
      {:ok, _} = Characters.set_active_character(ctx.player, ctx.second)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/rooms/#{location}")

      assert has_element?(lv, "#message-form-0 option[selected][value='#{ctx.second.id}']")
      assert has_element?(lv, "#message-form-0 option[value='#{ctx.first.id}']")

      lv
      |> form("#message-form-0", message: %{character_id: ctx.first.id, body: "From Deckard"})
      |> render_submit()

      assert Repo.get_by(Message, body: "From Deckard").character_id == ctx.first.id
    end

    test "mail defaults to the active character as sender", ctx do
      {:ok, _} = Characters.set_active_character(ctx.player, ctx.second)
      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{ctx.story}/mail/new")
      assert has_element?(lv, "#mail-form option[selected][value='#{ctx.second.id}']")

      lv
      |> form("#mail-form",
        message: %{
          sender: ctx.first.id,
          recipient: ctx.second.id,
          subject: "Alt",
          body: "Me to me"
        }
      )
      |> render_submit()

      assert render(lv) =~ "another of your characters"
    end

    test "the market buys with the active character", ctx do
      story = enable_modules(ctx.story, [:items])
      {:ok, item} = Items.create_item(story, %{name: "Medkit", price: 10})
      {:ok, shop} = Items.create_shop(story, %{name: "Pharmacy"})
      {:ok, listing} = Items.create_listing(story, shop, %{item_id: item.id})
      {:ok, _} = Bank.adjust(ctx.second, 15)
      {:ok, _} = Characters.set_active_character(ctx.player, ctx.second)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{story}/market/#{shop}")

      lv
      |> form("#buy-form-#{listing.id}", %{"quantity" => "1"})
      |> render_submit()

      assert [%{quantity: 1}] = Items.inventory(Characters.get_character!(ctx.second.id))
      assert Items.inventory(Characters.get_character!(ctx.first.id)) == []
    end

    test "guilds are joined by the active character", ctx do
      story = enable_modules(ctx.story, [:guilds])
      {:ok, guild} = Guilds.create_guild(story, %{name: "Police", open_join: true})
      {:ok, _} = Guilds.create_rank(guild, %{name: "Cadet", position: 0})
      {:ok, _} = Characters.set_active_character(ctx.player, ctx.second)

      {:ok, lv, _} = live(conn_for(ctx.player), ~p"/g/#{story}/guilds/#{guild}")
      lv |> element("#request-join") |> render_click()

      assert [%{character_id: id}] = Guilds.list_pending(guild)
      assert id == ctx.second.id
    end
  end

  test "the GM sets the limit and the alt rules in the general tab", ctx do
    {:ok, lv, _} = live(conn_for(ctx.gm), ~p"/g/#{ctx.story}/gm")
    assert has_element?(lv, "#character-limit-settings")

    lv
    |> form("#general-form",
      story: %{max_characters_per_user: 3, block_alt_transfers: false, block_alt_mail: false}
    )
    |> render_submit()

    assert %{max_characters_per_user: 3, block_alt_transfers: false, block_alt_mail: false} =
             Stories.get_story!(ctx.story.id)
  end

  defp user(id), do: Repo.get!(TannhauserGate.Accounts.User, id)
end
