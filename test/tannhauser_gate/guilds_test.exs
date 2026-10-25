defmodule TannhauserGate.GuildsTest do
  use TannhauserGate.DataCase, async: true

  import TannhauserGate.AccountsFixtures
  import TannhauserGate.GameFixtures

  alias TannhauserGate.{Bank, Bookings, Characters, Forum, Guilds, Repo, Stories}
  alias TannhauserGate.Bank.Transaction
  alias TannhauserGate.Guilds.{Log, Membership}

  setup do
    {story, gm} = gdr_fixture()
    story = enable_modules(story, [:guilds])
    {:ok, master} = Stories.add_master(story, user_fixture().username)

    guild = guild_fixture(story, %{name: "Police", open_join: true})
    cadet = rank_fixture(guild, %{name: "Cadet", salary: 20, position: 0})
    captain = rank_fixture(guild, %{name: "Captain", salary: 80, position: 2, leader: true})

    alice = user_fixture()
    bob = user_fixture()

    %{
      story: story,
      gm: gm,
      master: master,
      guild: Guilds.get_guild(story, guild.id),
      cadet: cadet,
      captain: captain,
      alice: alice,
      a: character_fixture(alice, story),
      bob: bob,
      b: character_fixture(bob, story)
    }
  end

  defp guild_fixture(story, attrs) do
    {:ok, guild} =
      Guilds.create_guild(
        story,
        Enum.into(attrs, %{name: "Guild #{System.unique_integer([:positive])}"})
      )

    guild
  end

  defp rank_fixture(guild, attrs) do
    {:ok, rank} = Guilds.create_rank(guild, Enum.into(attrs, %{salary: 0, position: 0}))
    rank
  end

  defp reload(guild, membership), do: Guilds.get_membership(guild, membership.id)

  # Makes the character an active member through a master enrolment.
  defp enrol!(ctx, character, rank \\ nil) do
    {:ok, m} = Guilds.enrol(ctx.master, ctx.story, ctx.guild, character.id, rank && rank.id)
    reload(ctx.guild, m)
  end

  defp actions(guild), do: guild |> Guilds.list_logs() |> Enum.map(& &1.action)

  describe "guilds and ranks" do
    test "names are unique per GDR and salaries can't be negative", %{story: story, guild: guild} do
      assert {:error, cs} = Guilds.create_guild(story, %{name: "Police"})
      assert errors_on(cs) != %{}
      {other, _} = gdr_fixture()
      assert {:ok, _} = Guilds.create_guild(other, %{name: "Police"})

      assert {:error, cs} = Guilds.create_rank(guild, %{name: "Bad", salary: -1, position: 0})
      assert errors_on(cs).salary != []
    end

    test "get_guild is scoped to the GDR", %{guild: guild} do
      {other, _} = gdr_fixture()
      assert Guilds.get_guild(other, guild.id) == nil
      assert Guilds.get_guild(other, "nope") == nil
    end
  end

  describe "membership flows" do
    test "request, approve, rank change and leave are logged", ctx do
      %{alice: alice, a: a, guild: guild, story: story, master: master} = ctx

      assert {:ok, m} = Guilds.request_join(alice, guild, a)
      assert m.status == "requested"
      assert {:error, :already_member} = Guilds.request_join(alice, guild, a)

      # Only the owner can ask with a character.
      assert {:error, _} = Guilds.request_join(ctx.bob, guild, a)

      # A non-manager can't approve.
      assert {:error, :unauthorized} =
               Guilds.approve_request(ctx.bob, story, guild, reload(guild, m))

      assert {:ok, m} = Guilds.approve_request(master, story, guild, reload(guild, m))
      m = reload(guild, m)
      assert m.status == "active"
      assert m.rank_id == ctx.cadet.id
      assert m.last_paid_at

      assert Guilds.active_member_user?(alice, guild.id)
      assert {:ok, _} = Guilds.set_rank(master, story, guild, m, ctx.captain.id)
      assert {:ok, _} = Guilds.leave(alice, guild, reload(guild, m))
      refute Guilds.membership_for(a, guild)

      assert actions(guild) == ["leave", "rank", "join", "request"]
      assert [%Log{user_id: user_id} | _] = Guilds.list_logs(guild)
      assert user_id == alice.id
    end

    test "invitation-only guilds: invite, accept or decline", ctx do
      %{alice: alice, a: a, b: b, bob: bob, story: story, master: master} = ctx
      {:ok, secret} = Guilds.create_guild(story, %{name: "Underground", open_join: false})

      assert {:error, :invitation_only} = Guilds.request_join(alice, secret, a)
      assert {:error, :unauthorized} = Guilds.invite(alice, story, secret, b.id)

      assert {:ok, ia} = Guilds.invite(master, story, secret, a.id)
      assert {:ok, ib} = Guilds.invite(master, story, secret, b.id)
      assert {:error, :already_member} = Guilds.invite(master, story, secret, a.id)

      # Only the character owner answers.
      assert {:error, _} = Guilds.accept_invitation(bob, secret, reload(secret, ia))
      assert {:ok, _} = Guilds.accept_invitation(alice, secret, reload(secret, ia))
      assert {:ok, _} = Guilds.decline_invitation(bob, secret, reload(secret, ib))

      assert [%{character_id: a_id}] = Guilds.list_members(secret)
      assert a_id == a.id
      assert Guilds.list_pending(secret) == []
    end

    test "masters reject requests and withdraw invitations", ctx do
      %{alice: alice, a: a, b: b, guild: guild, story: story, master: master} = ctx
      {:ok, r} = Guilds.request_join(alice, guild, a)
      {:ok, i} = Guilds.invite(master, story, guild, b.id)

      assert {:ok, _} = Guilds.reject_request(master, story, guild, reload(guild, r))
      assert {:ok, _} = Guilds.reject_request(master, story, guild, reload(guild, i))
      assert Guilds.list_pending(guild) == []
      assert Enum.take(actions(guild), 2) == ["cancel", "reject"]
    end

    test "NPCs can be enrolled only by masters and can't be invited", ctx do
      %{story: story, guild: guild, master: master} = ctx
      npc = npc_fixture(master, story)

      assert {:error, :character_not_found} = Guilds.invite(master, story, guild, npc.id)
      assert {:error, :unauthorized} = Guilds.enrol(ctx.alice, story, guild, npc.id)
      assert {:ok, _} = Guilds.enrol(master, story, guild, npc.id, ctx.captain.id)
      assert [%{rank_id: rank_id}] = Guilds.list_members(guild)
      assert rank_id == ctx.captain.id
    end

    test "unapproved characters can't join", ctx do
      user = user_fixture()
      draft = draft_character_fixture(user, ctx.story)
      assert {:error, :cannot_play} = Guilds.request_join(user, ctx.guild, draft)
    end

    test "the max guilds per character is enforced on activation", ctx do
      %{alice: alice, a: a, story: story, master: master, guild: guild} = ctx
      {:ok, other} = Guilds.create_guild(story, %{name: "Other", open_join: true})

      enrol!(ctx, a)
      assert {:error, :too_many_guilds} = Guilds.request_join(alice, other, a)

      # Invitations can be sent, but not accepted while the character is full.
      {:ok, inv} = Guilds.invite(master, story, other, a.id)

      assert {:error, :too_many_guilds} =
               Guilds.accept_invitation(alice, other, reload(other, inv))

      assert {:error, :already_member} = Guilds.enrol(master, story, other, a.id)
      assert {:ok, _} = Guilds.enrol(master, story, other, ctx.b.id)

      {:ok, story} = Stories.update_story_as_gm(story, %{max_guilds_per_character: 2})
      assert story.max_guilds_per_character == 2
      assert {:ok, _} = Guilds.accept_invitation(alice, other, reload(other, inv))
      assert length(Guilds.character_guilds(a)) == 2
      assert Guilds.membership_for(a, guild).status == "active"
    end
  end

  describe "leaders" do
    setup ctx do
      leader_user = user_fixture()
      leader = character_fixture(leader_user, ctx.story)
      enrol!(ctx, leader, ctx.captain)
      Map.merge(ctx, %{leader_user: leader_user, leader: leader})
    end

    test "manage non-leader members only", ctx do
      %{leader_user: lu, story: story, guild: guild, alice: alice, a: a} = ctx
      assert Guilds.leader?(lu, guild)
      assert Guilds.manager?(lu, story, guild)
      refute Guilds.manager?(alice, story, guild)

      {:ok, r} = Guilds.request_join(alice, guild, a)
      assert {:ok, _} = Guilds.approve_request(lu, story, guild, reload(guild, r))
      m = Guilds.membership_for(a, guild) |> then(&reload(guild, &1))

      # Leaders can't promote to a leader rank.
      assert {:error, :unauthorized} = Guilds.set_rank(lu, story, guild, m, ctx.captain.id)

      # Another leader is out of reach.
      {:ok, m} = Guilds.set_rank(ctx.master, story, guild, m, ctx.captain.id)
      m = reload(guild, m)
      assert {:error, :unauthorized} = Guilds.expel(lu, story, guild, m)

      # The member can't manage anyone once demoted.
      {:ok, m} = Guilds.set_rank(ctx.master, story, guild, m, ctx.cadet.id)
      assert {:ok, _} = Guilds.expel(lu, story, guild, reload(guild, m))
      refute Guilds.active_member_user?(alice, guild.id)

      # A leader can't expel themselves (they leave instead).
      own = Guilds.membership_for(ctx.leader, guild) |> then(&reload(guild, &1))
      assert {:error, :unauthorized} = Guilds.expel(lu, story, guild, own)
      assert {:error, :unauthorized} = Guilds.expel(alice, story, guild, own)
    end

    test "invite players", ctx do
      assert {:ok, %Membership{status: "invited"}} =
               Guilds.invite(ctx.leader_user, ctx.story, ctx.guild, ctx.b.id)
    end
  end

  describe "secret guilds" do
    test "are visible only to members and masters", ctx do
      %{story: story, alice: alice, bob: bob, master: master, a: a} = ctx
      {:ok, secret} = Guilds.create_guild(story, %{name: "Echo", secret: true})

      refute Guilds.visible?(bob, story, secret)
      refute Guilds.members_visible?(bob, story, secret)
      assert Guilds.visible?(master, story, secret)
      assert Guilds.members_visible?(master, story, secret)

      {:ok, inv} = Guilds.invite(master, story, secret, a.id)
      # Invited: sees the guild, not yet its members.
      assert Guilds.visible?(alice, story, secret)
      refute Guilds.members_visible?(alice, story, secret)
      assert secret.id in Enum.map(Guilds.list_visible_guilds(alice, story), & &1.id)
      refute secret.id in Enum.map(Guilds.list_visible_guilds(bob, story), & &1.id)

      {:ok, _} = Guilds.accept_invitation(alice, secret, reload(secret, inv))
      assert Guilds.members_visible?(alice, story, secret)

      # The sheet and the presence list hide the secret membership.
      assert [] = Guilds.character_guilds(a, bob)
      assert [_] = Guilds.character_guilds(a, alice)
      assert Guilds.public_guild_names(a) == []
    end

    test "nothing shows when the module is off", ctx do
      enrol!(ctx, ctx.a)
      assert [_] = Guilds.character_guilds(ctx.a, ctx.bob)
      assert Guilds.public_guild_names(ctx.a) == ["Police"]

      {:ok, _} = Stories.set_module_enabled(ctx.story, :guilds, false)
      assert Guilds.character_guilds(ctx.a, ctx.bob) == []
      assert Guilds.public_guild_names(ctx.a) == []

      assert {:error, :module_disabled} =
               Guilds.request_join(ctx.bob, ctx.guild, ctx.b)
    end
  end

  describe "cross-GDR ids" do
    test "characters, ranks and memberships of another GDR are rejected", ctx do
      %{story: story, guild: guild, master: master} = ctx
      {other, other_gm} = gdr_fixture()
      other = enable_modules(other, [:guilds])
      foreign = character_fixture(user_fixture(), other)
      {:ok, other_guild} = Guilds.create_guild(other, %{name: "Foreign", open_join: true})
      foreign_rank = rank_fixture(other_guild, %{name: "Boss"})

      assert {:error, :character_not_found} = Guilds.invite(master, story, guild, foreign.id)
      assert {:error, :character_not_found} = Guilds.enrol(master, story, guild, foreign.id)

      assert {:error, :character_not_found} =
               Guilds.request_join(Repo.preload(foreign, :user).user, guild, foreign)

      # A master of this GDR can't manage the other GDR's guild.
      assert {:error, _} = Guilds.invite(master, story, other_guild, ctx.a.id)
      assert {:error, :unauthorized} = Guilds.invite(master, other, other_guild, ctx.a.id)

      m = enrol!(ctx, ctx.a)
      assert {:error, :rank_not_found} = Guilds.set_rank(master, story, guild, m, foreign_rank.id)
      assert Guilds.get_membership(other_guild, m.id) == nil

      {:ok, om} = Guilds.enrol(other_gm, other, other_guild, foreign.id)
      assert {:error, _} = Guilds.expel(master, story, guild, reload(other_guild, om))
    end
  end

  describe "salaries" do
    test "active members are paid once per interval", ctx do
      m = enrol!(ctx, ctx.a)
      now = DateTime.add(m.last_paid_at, 25 * 3600, :second)

      # Not due right after joining.
      assert Bank.pay_guild_salaries(m.last_paid_at) == 0
      assert Bank.pay_guild_salaries(now) == 1
      assert Bank.pay_guild_salaries(now) == 0
      assert Characters.get_character!(ctx.a.id).balance == 20

      assert [%Transaction{kind: "pay", amount: 20, note: "Guild salary: Police (Cadet)"}] =
               Repo.all(from t in Transaction, where: t.to_character_id == ^ctx.a.id)

      later = DateTime.add(now, 25 * 3600, :second)
      assert Bank.pay_due(later) >= 1
      assert Characters.get_character!(ctx.a.id).balance == 40
    end

    test "zero salaries, pending members and disabled modules aren't paid", ctx do
      unpaid = rank_fixture(ctx.guild, %{name: "Volunteer", salary: 0, position: 1})
      enrol!(ctx, ctx.a, unpaid)
      {:ok, _} = Guilds.request_join(ctx.bob, ctx.guild, ctx.b)
      now = DateTime.add(DateTime.utc_now(), 48 * 3600, :second)
      assert Bank.pay_guild_salaries(now) == 0

      m = enrol!(ctx, character_fixture(user_fixture(), ctx.story))
      {:ok, _} = Stories.set_module_enabled(ctx.story, :guilds, false)
      assert Bank.pay_guild_salaries(DateTime.add(m.last_paid_at, 48 * 3600, :second)) == 0
    end
  end

  describe "forum guild sections" do
    test "are visible only to active members and masters", ctx do
      %{story: story, guild: guild, alice: alice, bob: bob, master: master} = ctx

      assert {:error, cs} = Forum.create_section(story, %{name: "Den", visibility: "guild"})
      assert errors_on(cs).guild_id != []

      {other, _} = gdr_fixture()
      {:ok, foreign} = Guilds.create_guild(other, %{name: "Foreign"})

      assert {:error, cs} =
               Forum.create_section(story, %{
                 name: "Den",
                 visibility: "guild",
                 guild_id: foreign.id
               })

      assert errors_on(cs).guild_id != []

      {:ok, section} =
        Forum.create_section(story, %{name: "Den", visibility: "guild", guild_id: guild.id})

      enrol!(ctx, ctx.a)
      assert Forum.can_view_section?(alice, story, section)
      assert Forum.can_view_section?(master, story, section)
      refute Forum.can_view_section?(bob, story, section)

      {:ok, story} = Stories.set_module_enabled(story, :guilds, false)
      refute Forum.can_view_section?(alice, story, section)
      assert Forum.can_view_section?(master, story, section)
    end
  end

  describe "guild rooms" do
    test "only active members and masters can access them", ctx do
      %{story: story, guild: guild, alice: alice, bob: bob, master: master} = ctx
      location = location_fixture(story, %{guild_id: guild.id})
      location = Stories.get_location!(location.id)

      enrol!(ctx, ctx.a)
      assert Bookings.can_access?(alice, location)
      assert Bookings.can_access?(master, location)
      refute Bookings.can_access?(bob, location)
      assert Bookings.guild_locked?(bob, location)

      {:ok, _} = Stories.set_module_enabled(story, :guilds, false)
      location = Stories.get_location!(location.id)
      assert Bookings.can_access?(bob, location)
    end

    test "rooms can't reference another GDR's guild", ctx do
      {other, _} = gdr_fixture()
      {:ok, foreign} = Guilds.create_guild(other, %{name: "Foreign"})

      assert {:error, cs} =
               Stories.create_location(ctx.story, %{
                 name: "X",
                 area: "0,0 10,0 10,10",
                 guild_id: foreign.id
               })

      assert errors_on(cs).guild_id != []
    end

    test "deleting a guild frees its rooms", ctx do
      location = location_fixture(ctx.story, %{guild_id: ctx.guild.id})
      {:ok, _} = Guilds.delete_guild(ctx.guild)
      assert Stories.get_location!(location.id).guild_id == nil
    end
  end
end
