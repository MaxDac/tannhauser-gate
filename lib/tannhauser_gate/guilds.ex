defmodule TannhauserGate.Guilds do
  @moduledoc """
  Guilds and factions, the `:guilds` optional module.

    * **Guilds** (managed by the masters): a name, a Markdown description, an
      optional emblem, `secret` membership and `open_join` (join by request)
      or invitation only (`TannhauserGate.Guilds.Guild`), with ordered
      **ranks** carrying a salary and a `leader` flag.
    * **Memberships** (`TannhauserGate.Guilds.Membership`): a character asks
      to join an open guild and a leader or a master approves or rejects the
      request; a leader or a master invites a character and its owner accepts
      or declines. Members leave; leaders change the rank of and expel the
      non-leader members, masters manage everybody. A character can be an
      active member of at most `stories.max_guilds_per_character` guilds,
      enforced (under a row lock on the character) whenever a membership
      becomes active.
    * Every change is recorded in the guild **log** (`TannhauserGate.Guilds.Log`).
    * Salaries are paid by `TannhauserGate.Bank.pay_due/1`; guild forum
      sections (`TannhauserGate.Forum`) and guild rooms
      (`TannhauserGate.Bookings.can_access?/3`) are reserved to the members.

  Every id coming from the outside is scoped to the guild's GDR and the
  membership flows return `{:error, :module_disabled}` when the module is off.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Guilds.{Guild, Log, Membership, Rank}
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  @doc "Whether the guilds module is enabled for the story (or story id)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :guilds)
  def enabled?(story_id) when is_integer(story_id), do: enabled?(Stories.get_story(story_id))
  def enabled?(_), do: false

  ## Guilds

  @doc "The guilds of a story, by position then name, with their ranks."
  def list_guilds(%Story{id: story_id}) do
    Repo.all(
      from g in Guild,
        where: g.story_id == ^story_id,
        order_by: [asc: g.position, asc: g.name],
        preload: :ranks
    )
  end

  @doc "The guilds of the story the user can see (see `visible?/3`)."
  def list_visible_guilds(user, %Story{} = story) do
    guilds = list_guilds(story)

    if Stories.master?(user, story) do
      guilds
    else
      known = user |> user_memberships(story) |> MapSet.new(& &1.guild_id)
      Enum.filter(guilds, &(not &1.secret or MapSet.member?(known, &1.id)))
    end
  end

  @doc "A guild of the story (`id` may be a string) with its ranks, or nil."
  def get_guild(%Story{id: story_id}, id) do
    case parse_id(id) do
      nil -> nil
      id -> Guild |> Repo.get_by(id: id, story_id: story_id) |> Repo.preload(:ranks)
    end
  end

  def get_guild!(%Story{} = story, id),
    do: get_guild(story, id) || raise(Ecto.NoResultsError, queryable: Guild)

  @doc "Creates a guild. `emblem_path` is an already stored image."
  def create_guild(%Story{} = story, attrs, emblem_path \\ nil) do
    %Guild{story_id: story.id}
    |> Guild.changeset(attrs)
    |> maybe_put_emblem(emblem_path)
    |> Repo.insert()
  end

  def update_guild(%Guild{} = guild, attrs, emblem_path \\ nil) do
    guild
    |> Guild.changeset(attrs)
    |> maybe_put_emblem(emblem_path)
    |> Repo.update()
  end

  @doc "Deletes a guild with its ranks, memberships and log."
  def delete_guild(%Guild{} = guild), do: Repo.delete(guild)

  def change_guild(%Guild{} = guild, attrs \\ %{}), do: Guild.changeset(guild, attrs)

  def remove_emblem(%Guild{} = guild), do: guild |> Guild.emblem_changeset(nil) |> Repo.update()

  defp maybe_put_emblem(changeset, nil), do: changeset
  defp maybe_put_emblem(changeset, path), do: Guild.emblem_changeset(changeset, path)

  ## Ranks

  @doc "A rank of the guild (`id` may be a string), or nil."
  def get_rank(%Guild{id: guild_id}, id) do
    case parse_id(id) do
      nil -> nil
      id -> Repo.get_by(Rank, id: id, guild_id: guild_id)
    end
  end

  def create_rank(%Guild{} = guild, attrs) do
    %Rank{guild_id: guild.id} |> Rank.changeset(attrs) |> Repo.insert()
  end

  def update_rank(%Rank{} = rank, attrs), do: rank |> Rank.changeset(attrs) |> Repo.update()

  @doc "Deletes a rank; its members are left without a rank (and salary)."
  def delete_rank(%Rank{} = rank), do: Repo.delete(rank)

  def change_rank(%Rank{} = rank, attrs \\ %{}), do: Rank.changeset(rank, attrs)

  # The rank given to new members: the first non-leader rank, else the first.
  defp default_rank(%Guild{} = guild) do
    ranks = guild |> Repo.preload(:ranks) |> Map.fetch!(:ranks)
    Enum.find(ranks, &(not &1.leader)) || List.first(ranks)
  end

  ## Visibility and roles

  @doc """
  Whether the user can see the guild: public guilds are visible to everyone,
  secret ones to the masters and to the users whose character is a member,
  was invited or asked to join.
  """
  def visible?(user, %Story{} = story, %Guild{} = guild) do
    not guild.secret or Stories.master?(user, story) or user_in_guild?(user, guild.id)
  end

  @doc """
  Whether the user can see the members of the guild: everyone for public
  guilds, only the masters and the active members for secret ones.
  """
  def members_visible?(user, %Story{} = story, %Guild{} = guild) do
    not guild.secret or Stories.master?(user, story) or active_member_user?(user, guild.id)
  end

  @doc "Whether one of the user's (player) characters is an active member of the guild."
  def active_member_user?(%User{id: user_id}, guild_id) when not is_nil(guild_id) do
    Repo.exists?(
      from m in Membership,
        join: c in assoc(m, :character),
        where:
          m.guild_id == ^guild_id and m.status == "active" and c.user_id == ^user_id and
            not c.is_npc
    )
  end

  def active_member_user?(_, _), do: false

  defp user_in_guild?(%User{id: user_id}, guild_id) do
    Repo.exists?(
      from m in Membership,
        join: c in assoc(m, :character),
        where: m.guild_id == ^guild_id and c.user_id == ^user_id and not c.is_npc
    )
  end

  defp user_in_guild?(_, _), do: false

  @doc "Whether one of the user's characters is an active member of a leader rank."
  def leader?(%User{id: user_id}, %Guild{id: guild_id}) do
    Repo.exists?(
      from m in Membership,
        join: c in assoc(m, :character),
        join: r in assoc(m, :rank),
        where:
          m.guild_id == ^guild_id and m.status == "active" and c.user_id == ^user_id and
            not c.is_npc and r.leader
    )
  end

  def leader?(_, _), do: false

  @doc "Whether the user manages the guild: a master or one of its leaders."
  def manager?(user, %Story{} = story, %Guild{} = guild),
    do: Stories.master?(user, story) or leader?(user, guild)

  ## Memberships

  @doc "The active members of a guild with their character and rank, highest ranks first."
  def list_members(%Guild{id: guild_id}) do
    Repo.all(
      from m in Membership,
        join: c in assoc(m, :character),
        left_join: r in assoc(m, :rank),
        where: m.guild_id == ^guild_id and m.status == "active",
        order_by: [desc_nulls_last: r.position, asc: c.name],
        preload: [character: c, rank: r]
    )
  end

  @doc "The pending requests and invitations of a guild."
  def list_pending(%Guild{id: guild_id}) do
    Repo.all(
      from m in Membership,
        join: c in assoc(m, :character),
        where: m.guild_id == ^guild_id and m.status in ["requested", "invited"],
        order_by: [asc: m.inserted_at, asc: m.id],
        preload: [character: c]
    )
  end

  @doc "The number of active members of every guild of the story."
  def member_counts(%Story{id: story_id}) do
    Repo.all(
      from m in Membership,
        join: g in assoc(m, :guild),
        where: g.story_id == ^story_id and m.status == "active",
        group_by: m.guild_id,
        select: {m.guild_id, count(m.id)}
    )
    |> Map.new()
  end

  @doc "Every membership (any status) of the user's player characters in the story."
  def user_memberships(%User{id: user_id}, %Story{id: story_id}) do
    Repo.all(
      from m in Membership,
        join: c in assoc(m, :character),
        join: g in assoc(m, :guild),
        where: c.user_id == ^user_id and not c.is_npc and c.story_id == ^story_id,
        where: g.story_id == ^story_id,
        order_by: [asc: g.position, asc: g.name],
        preload: [:rank, character: c, guild: g]
    )
  end

  def user_memberships(_, _), do: []

  @doc """
  The guilds a character is an active member of, with guild and rank. With a
  viewer, the secret guilds are kept only for the masters and the members.
  Empty when the module is disabled.
  """
  def character_guilds(%Character{} = character, viewer \\ :all) do
    story = Stories.get_story(character.story_id)

    if enabled?(story) do
      memberships =
        Repo.all(
          from m in Membership,
            join: g in assoc(m, :guild),
            left_join: r in assoc(m, :rank),
            where: m.character_id == ^character.id and m.status == "active",
            order_by: [asc: g.position, asc: g.name],
            preload: [guild: g, rank: r]
        )

      case viewer do
        :all -> memberships
        user -> Enum.filter(memberships, &members_visible?(user, story, &1.guild))
      end
    else
      []
    end
  end

  @doc "The names of the public guilds a character is an active member of (presence list)."
  def public_guild_names(%Character{id: id, story_id: story_id}) do
    if enabled?(story_id) do
      Repo.all(
        from m in Membership,
          join: g in assoc(m, :guild),
          where: m.character_id == ^id and m.status == "active" and not g.secret,
          order_by: [asc: g.position, asc: g.name],
          select: g.name
      )
    else
      []
    end
  end

  def public_guild_names(_), do: []

  @doc "A membership of the guild (`id` may be a string) with its character and rank, or nil."
  def get_membership(%Guild{id: guild_id}, id) do
    case parse_id(id) do
      nil ->
        nil

      id ->
        Membership
        |> Repo.get_by(id: id, guild_id: guild_id)
        |> Repo.preload([:character, :rank])
    end
  end

  @doc "The membership (any status) of the character in the guild, or nil."
  def membership_for(%Character{id: character_id}, %Guild{id: guild_id}) do
    Repo.one(
      from m in Membership,
        where: m.guild_id == ^guild_id and m.character_id == ^character_id,
        preload: [:rank]
    )
  end

  def membership_for(_, _), do: nil

  @doc """
  The characters a manager can invite: approved player characters of the GDR
  without any membership in the guild.
  """
  def invite_candidates(%Guild{id: guild_id, story_id: story_id}) do
    taken = from m in Membership, where: m.guild_id == ^guild_id, select: m.character_id

    Repo.all(
      from c in Character,
        where:
          c.story_id == ^story_id and not c.is_npc and c.approval_status == "approved" and
            c.id not in subquery(taken),
        order_by: [asc: c.name]
    )
  end

  @doc "Characters (NPCs included) of the GDR not yet in the guild, for masters to enrol."
  def enrol_candidates(%Guild{id: guild_id, story_id: story_id}) do
    taken = from m in Membership, where: m.guild_id == ^guild_id, select: m.character_id

    Repo.all(
      from c in Character,
        where: c.story_id == ^story_id and c.id not in subquery(taken),
        order_by: [asc: c.name]
    )
  end

  ## Flows

  @doc """
  The user's character asks to join an open guild of its GDR.
  """
  def request_join(%User{} = user, %Guild{} = guild, %Character{} = character) do
    with :ok <- check_enabled(guild),
         :ok <- check_owner(user, character),
         true <- character.story_id == guild.story_id || {:error, :character_not_found},
         true <- Characters.can_play?(character) || {:error, :cannot_play},
         true <- guild.open_join || {:error, :invitation_only},
         nil <- membership_for(character, guild),
         :ok <- check_room(character, guild) do
      insert_pending(guild, character, "requested", user, "request")
    else
      %Membership{} -> {:error, :already_member}
      {:error, _} = error -> error
    end
  end

  @doc "A leader or a master invites an approved player character of the GDR."
  def invite(%User{} = user, %Story{} = story, %Guild{} = guild, character_id) do
    with :ok <- check_guild(story, guild),
         :ok <- check_enabled(guild),
         true <- manager?(user, story, guild) || {:error, :unauthorized},
         %Character{is_npc: false} = character <- fetch_character(guild.story_id, character_id),
         true <- Characters.can_play?(character) || {:error, :cannot_play},
         nil <- membership_for(character, guild) do
      insert_pending(guild, character, "invited", user, "invite")
    else
      %Membership{} -> {:error, :already_member}
      nil -> {:error, :character_not_found}
      %Character{} -> {:error, :character_not_found}
      {:error, _} = error -> error
    end
  end

  @doc "A master enrols any character of the GDR (NPCs included) directly, with a rank."
  def enrol(%User{} = user, %Story{} = story, %Guild{} = guild, character_id, rank_id \\ nil) do
    with :ok <- check_guild(story, guild),
         :ok <- check_enabled(guild),
         true <- Stories.master?(user, story) || {:error, :unauthorized},
         %Character{} = character <- fetch_character(guild.story_id, character_id),
         nil <- membership_for(character, guild),
         {:ok, rank} <- pick_rank(guild, rank_id),
         :ok <- check_room(character, guild),
         {:ok, membership} <- insert_pending(guild, character, "invited", user, nil) do
      case activate(membership, guild, rank, user) do
        {:ok, _} = ok ->
          ok

        {:error, _} = error ->
          Repo.delete_all(from m in Membership, where: m.id == ^membership.id)
          error
      end
    else
      %Membership{} -> {:error, :already_member}
      nil -> {:error, :character_not_found}
      {:error, _} = error -> error
    end
  end

  @doc "The owner of an invited character accepts the invitation."
  def accept_invitation(%User{} = user, %Guild{} = guild, %Membership{} = membership) do
    with :ok <- check_membership(guild, membership, "invited"),
         :ok <- check_owner(user, character_of(membership)) do
      activate(membership, guild, default_rank(guild), user)
    end
  end

  @doc "The owner of an invited character declines the invitation."
  def decline_invitation(%User{} = user, %Guild{} = guild, %Membership{} = membership) do
    with :ok <- check_membership(guild, membership, "invited"),
         :ok <- check_owner(user, character_of(membership)) do
      remove(membership, guild, user, "decline")
    end
  end

  @doc "The owner of a character withdraws its request to join."
  def cancel_request(%User{} = user, %Guild{} = guild, %Membership{} = membership) do
    with :ok <- check_membership(guild, membership, "requested"),
         :ok <- check_owner(user, character_of(membership)) do
      remove(membership, guild, user, "cancel")
    end
  end

  @doc "A leader or a master approves a request to join."
  def approve_request(%User{} = user, %Story{} = story, %Guild{} = guild, %Membership{} = m) do
    with :ok <- check_guild(story, guild),
         :ok <- check_membership(guild, m, "requested"),
         true <- manager?(user, story, guild) || {:error, :unauthorized} do
      activate(m, guild, default_rank(guild), user)
    end
  end

  @doc "A leader or a master rejects a request to join (or withdraws an invitation)."
  def reject_request(%User{} = user, %Story{} = story, %Guild{} = guild, %Membership{} = m) do
    with :ok <- check_guild(story, guild),
         :ok <- check_enabled(guild),
         true <- m.guild_id == guild.id || {:error, :membership_not_found},
         true <- m.status in ["requested", "invited"] || {:error, :invalid_status},
         true <- manager?(user, story, guild) || {:error, :unauthorized} do
      remove(m, guild, user, if(m.status == "requested", do: "reject", else: "cancel"))
    end
  end

  @doc "The owner of a member character leaves the guild."
  def leave(%User{} = user, %Guild{} = guild, %Membership{} = membership) do
    with :ok <- check_membership(guild, membership, "active"),
         :ok <- check_owner(user, character_of(membership)) do
      remove(membership, guild, user, "leave")
    end
  end

  @doc """
  Expels a member: masters expel anybody, leaders only the non-leader members
  other than their own characters.
  """
  def expel(%User{} = user, %Story{} = story, %Guild{} = guild, %Membership{} = membership) do
    with :ok <- check_guild(story, guild),
         :ok <- check_membership(guild, membership, "active"),
         :ok <- check_member_power(user, story, guild, membership) do
      remove(membership, guild, user, "expel")
    end
  end

  @doc """
  Changes the rank of a member: masters to any rank of the guild, leaders
  only for non-leader members and to non-leader ranks.
  """
  def set_rank(%User{} = user, %Story{} = story, %Guild{} = guild, %Membership{} = m, rank_id) do
    with :ok <- check_guild(story, guild),
         :ok <- check_membership(guild, m, "active"),
         :ok <- check_member_power(user, story, guild, m),
         %Rank{} = rank <- get_rank(guild, rank_id) || {:error, :rank_not_found},
         true <-
           (not rank.leader or Stories.master?(user, story)) || {:error, :unauthorized} do
      {:ok, updated} =
        Repo.transaction(fn ->
          updated = m |> Ecto.Changeset.change(rank_id: rank.id) |> Repo.update!()
          log!(guild, m.character_id, user, "rank", rank.name)
          updated
        end)

      {:ok, %{updated | rank: rank}}
    end
  end

  ## Log

  @doc "The latest entries of the guild log, newest first."
  def list_logs(%Guild{id: guild_id}, limit \\ 50) do
    Repo.all(
      from l in Log,
        where: l.guild_id == ^guild_id,
        order_by: [desc: l.inserted_at, desc: l.id],
        limit: ^limit,
        preload: [:character, :user]
    )
  end

  def action_label("request"), do: "asked to join"
  def action_label("invite"), do: "was invited"
  def action_label("join"), do: "joined"
  def action_label("decline"), do: "declined the invitation"
  def action_label("reject"), do: "was rejected"
  def action_label("cancel"), do: "request or invitation withdrawn"
  def action_label("leave"), do: "left"
  def action_label("expel"), do: "was expelled"
  def action_label("rank"), do: "is now"
  def action_label(other), do: other

  def status_label("requested"), do: "Request pending"
  def status_label("invited"), do: "Invited"
  def status_label("active"), do: "Member"
  def status_label(other), do: other

  def error_message(:module_disabled), do: "Guilds are not enabled in this GDR."
  def error_message(:unauthorized), do: "You can't do that in this guild."
  def error_message(:character_not_found), do: "That character can't join this guild."
  def error_message(:cannot_play), do: "That character cannot play yet."
  def error_message(:invitation_only), do: "This guild recruits by invitation only."

  def error_message(:already_member),
    do: "That character already belongs to, was invited to or asked to join this guild."

  def error_message(:too_many_guilds),
    do: "That character is already in the maximum number of guilds."

  def error_message(:membership_not_found), do: "That membership does not exist."
  def error_message(:invalid_status), do: "That membership has changed in the meantime."
  def error_message(:rank_not_found), do: "That rank does not exist in this guild."
  def error_message(:guild_not_found), do: "That guild does not exist in this GDR."
  def error_message(_), do: "Something went wrong."

  ## Helpers

  defp check_enabled(%Guild{story_id: story_id}),
    do: if(enabled?(story_id), do: :ok, else: {:error, :module_disabled})

  defp check_guild(%Story{id: story_id}, %Guild{story_id: story_id}), do: :ok
  defp check_guild(_, _), do: {:error, :guild_not_found}

  defp check_owner(%User{id: user_id}, %Character{user_id: user_id, is_npc: false}), do: :ok
  defp check_owner(_, _), do: {:error, :unauthorized}

  defp character_of(%Membership{} = m), do: Repo.preload(m, :character).character

  defp check_membership(%Guild{} = guild, %Membership{} = m, status) do
    cond do
      m.guild_id != guild.id -> {:error, :membership_not_found}
      m.status != status -> {:error, :invalid_status}
      true -> check_enabled(guild)
    end
  end

  # Masters act on anybody; leaders on non-leader members other than their
  # own characters.
  defp check_member_power(user, story, guild, %Membership{} = m) do
    m = Repo.preload(m, [:character, :rank])

    cond do
      Stories.master?(user, story) -> :ok
      not leader?(user, guild) -> {:error, :unauthorized}
      m.rank && m.rank.leader -> {:error, :unauthorized}
      m.character.user_id == user.id and not m.character.is_npc -> {:error, :unauthorized}
      true -> :ok
    end
  end

  # Whether the character can still become an active member of one more guild.
  defp check_room(%Character{} = character, %Guild{} = guild) do
    max = Stories.get_story(character.story_id).max_guilds_per_character || 1

    count =
      Repo.aggregate(
        from(m in Membership,
          where:
            m.character_id == ^character.id and m.status == "active" and
              m.guild_id != ^guild.id
        ),
        :count
      )

    if count < max, do: :ok, else: {:error, :too_many_guilds}
  end

  defp pick_rank(guild, rank_id) when rank_id in [nil, ""], do: {:ok, default_rank(guild)}

  defp pick_rank(guild, rank_id) do
    case get_rank(guild, rank_id) do
      nil -> {:error, :rank_not_found}
      rank -> {:ok, rank}
    end
  end

  defp insert_pending(guild, character, status, user, action) do
    Repo.transaction(fn ->
      changeset =
        %Membership{guild_id: guild.id, character_id: character.id, status: status}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.unique_constraint([:guild_id, :character_id],
          name: :guild_memberships_guild_id_character_id_index
        )

      case Repo.insert(changeset) do
        {:ok, membership} ->
          if action, do: log!(guild, character.id, user, action)
          %{membership | character: character}

        {:error, _} ->
          Repo.rollback(:already_member)
      end
    end)
  end

  # Makes the membership active with the rank, enforcing the GDR's maximum
  # number of guilds per character under a lock on the character row. The
  # salary clock starts now.
  defp activate(%Membership{} = membership, guild, rank, user) do
    Repo.transaction(fn ->
      character =
        Repo.one!(
          from c in Character, where: c.id == ^membership.character_id, lock: "FOR UPDATE"
        )

      current =
        Repo.one(from m in Membership, where: m.id == ^membership.id, lock: "FOR UPDATE")

      with %Membership{status: status} when status != "active" <- current,
           :ok <- check_room(character, guild) do
        updated =
          current
          |> Ecto.Changeset.change(
            status: "active",
            rank_id: rank && rank.id,
            last_paid_at: DateTime.utc_now(:second)
          )
          |> Repo.update!()

        log!(guild, character.id, user, "join", rank && rank.name)
        %{updated | character: character, rank: rank}
      else
        {:error, reason} -> Repo.rollback(reason)
        _ -> Repo.rollback(:invalid_status)
      end
    end)
  end

  defp remove(%Membership{} = membership, guild, user, action) do
    Repo.transaction(fn ->
      {count, _} = Repo.delete_all(from m in Membership, where: m.id == ^membership.id)
      if count == 0, do: Repo.rollback(:invalid_status)
      log!(guild, membership.character_id, user, action)
      membership
    end)
  end

  defp log!(guild, character_id, user, action, rank_name \\ nil) do
    Repo.insert!(%Log{
      story_id: guild.story_id,
      guild_id: guild.id,
      character_id: character_id,
      user_id: user && user.id,
      action: action,
      rank_name: rank_name
    })
  end

  defp fetch_character(story_id, id) do
    case parse_id(id) do
      nil -> nil
      id -> Repo.get_by(Character, id: id, story_id: story_id)
    end
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end
