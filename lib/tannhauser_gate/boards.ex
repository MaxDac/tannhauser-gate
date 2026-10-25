defmodule TannhauserGate.Boards do
  @moduledoc """
  Bulletin boards ("bacheche"), the `:boards` optional module.

  ## Announcements

  The masters post GDR announcements (`TannhauserGate.Boards.Announcement`),
  shown on the GDR home page, pinned ones first, then newest first. Expired
  announcements are hidden from the home page (the masters still manage
  them). Each user has an unread count: the announcements published after the
  last time they opened the home page (`TannhauserGate.Boards.AnnouncementRead`).

  ## Notice boards

  The masters hang boards (`TannhauserGate.Boards.Board`) in a room or in a
  zone (shown in every room of the zone). Players post short in-character
  notices (`TannhauserGate.Boards.Notice`) as a character they can act as;
  the author deletes their notices and the masters delete any. A board can be
  restricted to a guild when the guilds module is on: only the players of
  its active members and the masters see and use it (the same rule as
  guild rooms, see `TannhauserGate.Bookings.can_access?/2`).

  Changes are broadcast on `topic/1` as `{:boards, event, payload}`.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Boards.{Announcement, AnnouncementRead, Board, Notice}
  alias TannhauserGate.{Characters, Guilds, Repo, Stories}
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.{Location, Story}

  @pubsub TannhauserGate.PubSub

  def topic(story_id), do: "boards:story:#{story_id}"

  def subscribe(story_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(story_id))

  defp broadcast(story_id, event, payload) do
    Phoenix.PubSub.broadcast(@pubsub, topic(story_id), {:boards, event, payload})
  end

  defp broadcast_result({:ok, %{story_id: story_id} = record} = result, event) do
    broadcast(story_id, event, record)
    result
  end

  defp broadcast_result(result, _event), do: result

  @doc "Whether the boards module is enabled for the story (or story id)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :boards)
  def enabled?(story_id) when is_integer(story_id), do: enabled?(Stories.get_story(story_id))
  def enabled?(_), do: false

  ## Announcements

  @doc """
  The announcements shown on the GDR home: not expired, pinned first, then
  newest first. Empty when the module is disabled.
  """
  def list_announcements(%Story{id: story_id} = story) do
    if enabled?(story) do
      now = DateTime.utc_now()

      Repo.all(
        from a in Announcement,
          where: a.story_id == ^story_id and (is_nil(a.expires_at) or a.expires_at > ^now),
          order_by: [desc: a.pinned, desc: a.inserted_at],
          preload: :user
      )
    else
      []
    end
  end

  @doc "Every announcement of the story (expired ones included), newest first: for the masters."
  def list_all_announcements(%Story{id: story_id}) do
    Repo.all(
      from a in Announcement,
        where: a.story_id == ^story_id,
        order_by: [desc: a.pinned, desc: a.inserted_at],
        preload: :user
    )
  end

  def get_announcement(%Story{id: story_id}, id) do
    case Integer.parse(to_string(id)) do
      {id, ""} ->
        Repo.get_by(Announcement, id: id, story_id: story_id)

      _ ->
        nil
    end
  end

  def change_announcement(%Announcement{} = announcement, attrs \\ %{}),
    do: Announcement.changeset(announcement, attrs)

  @doc "Posts an announcement (masters only)."
  def create_announcement(user, %Story{} = story, attrs) do
    with :ok <- check_master(user, story) do
      %Announcement{story_id: story.id, user_id: user.id}
      |> Announcement.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result(:announcement)
    end
  end

  @doc "Edits an announcement (masters only)."
  def update_announcement(user, %Story{} = story, %Announcement{} = announcement, attrs) do
    with :ok <- check_master(user, story),
         :ok <- same_story(announcement, story) do
      announcement
      |> Announcement.changeset(attrs)
      |> Repo.update()
      |> broadcast_result(:announcement)
    end
  end

  @doc "Deletes an announcement (masters only)."
  def delete_announcement(user, %Story{} = story, %Announcement{} = announcement) do
    with :ok <- check_master(user, story),
         :ok <- same_story(announcement, story) do
      announcement |> Repo.delete() |> broadcast_result(:announcement)
    end
  end

  @doc """
  How many visible announcements were published after the user last opened
  the GDR home page. Zero when the module is disabled.
  """
  def unread_count(%{id: _} = user, %Story{id: story_id} = story) do
    if enabled?(story) do
      now = DateTime.utc_now()

      from(a in Announcement,
        where: a.story_id == ^story_id and (is_nil(a.expires_at) or a.expires_at > ^now)
      )
      |> published_after(last_seen_at(user, story))
      |> Repo.aggregate(:count)
    else
      0
    end
  end

  def unread_count(_, _), do: 0

  defp published_after(query, nil), do: query
  defp published_after(query, last_seen), do: where(query, [a], a.inserted_at > ^last_seen)

  @doc "When the user last opened the announcements of the story, or nil."
  def last_seen_at(%{id: user_id}, %Story{id: story_id}) do
    Repo.one(
      from r in AnnouncementRead,
        where: r.user_id == ^user_id and r.story_id == ^story_id,
        select: r.last_seen_at
    )
  end

  def last_seen_at(_, _), do: nil

  @doc "Marks every announcement of the story as read by the user."
  def mark_announcements_read(%{id: user_id}, %Story{id: story_id}) do
    now = DateTime.utc_now()

    Repo.insert_all(
      AnnouncementRead,
      [%{user_id: user_id, story_id: story_id, last_seen_at: now}],
      on_conflict: [set: [last_seen_at: now]],
      conflict_target: [:user_id, :story_id]
    )

    broadcast(story_id, :read, %{user_id: user_id})
    :ok
  end

  def mark_announcements_read(_, _), do: :ok

  ## Boards

  @doc "The boards of the story the user can see, by name, with their room, zone and guild."
  def list_boards(%Story{id: story_id} = story, user) do
    from(b in Board,
      where: b.story_id == ^story_id,
      order_by: [asc: b.name, asc: b.id],
      preload: [:location, :zone, :guild]
    )
    |> Repo.all()
    |> Enum.filter(&accessible?(user, story, &1))
  end

  @doc "Every board of the story, for the masters."
  def list_all_boards(%Story{id: story_id}) do
    Repo.all(
      from b in Board,
        where: b.story_id == ^story_id,
        order_by: [asc: b.name, asc: b.id],
        preload: [:location, :zone, :guild]
    )
  end

  @doc """
  The boards hung in a room: those of the room and those of its zone that the
  user can see. Empty when the module is disabled.
  """
  def boards_for_location(%Location{} = location, user) do
    story = Stories.get_story(location.story_id)

    if enabled?(story) do
      from(b in Board,
        where: b.story_id == ^location.story_id,
        order_by: [asc: b.name, asc: b.id],
        preload: [:location, :zone, :guild]
      )
      |> where_at_location(location)
      |> Repo.all()
      |> Enum.filter(&accessible?(user, story, &1))
    else
      []
    end
  end

  defp where_at_location(query, %Location{id: location_id, zone_id: nil}),
    do: where(query, [b], b.location_id == ^location_id)

  defp where_at_location(query, %Location{id: location_id, zone_id: zone_id}),
    do: where(query, [b], b.location_id == ^location_id or b.zone_id == ^zone_id)

  @doc "A board of the story, or nil."
  def get_board(%Story{id: story_id}, id) do
    case Integer.parse(to_string(id)) do
      {id, ""} ->
        Repo.one(
          from b in Board,
            where: b.id == ^id and b.story_id == ^story_id,
            preload: [:location, :zone, :guild]
        )

      _ ->
        nil
    end
  end

  @doc """
  Whether the user can see and use the board: unrestricted boards are open to
  every member; guild boards (guilds module on) to the masters and the players
  of the guild's active members.
  """
  def accessible?(_user, _story, %Board{guild_id: nil}), do: true

  def accessible?(user, %Story{} = story, %Board{guild_id: guild_id}) do
    not Guilds.enabled?(story) or Stories.master?(user, story) or
      Guilds.active_member_user?(user, guild_id)
  end

  def change_board(%Board{} = board, attrs \\ %{}), do: Board.changeset(board, attrs)

  @doc "Creates a board (masters only); its room, zone and guild must belong to the story."
  def create_board(user, %Story{} = story, attrs) do
    with :ok <- check_master(user, story) do
      %Board{story_id: story.id}
      |> Board.changeset(attrs)
      |> validate_refs(story)
      |> Repo.insert()
      |> broadcast_result(:board)
    end
  end

  @doc "Updates a board (masters only)."
  def update_board(user, %Story{} = story, %Board{} = board, attrs) do
    with :ok <- check_master(user, story),
         :ok <- same_story(board, story) do
      board
      |> Board.changeset(attrs)
      |> validate_refs(story)
      |> Repo.update()
      |> broadcast_result(:board)
    end
  end

  @doc "Deletes a board and its notices (masters only)."
  def delete_board(user, %Story{} = story, %Board{} = board) do
    with :ok <- check_master(user, story),
         :ok <- same_story(board, story) do
      board |> Repo.delete() |> broadcast_result(:board)
    end
  end

  defp validate_refs(changeset, %Story{id: story_id}) do
    changeset
    |> validate_ref(:location_id, Location, story_id, "is not a room of this GDR")
    |> validate_ref(:zone_id, TannhauserGate.Zones.Zone, story_id, "is not a zone of this GDR")
    |> validate_ref(:guild_id, Guilds.Guild, story_id, "is not a guild of this GDR")
  end

  defp validate_ref(changeset, field, schema, story_id, message) do
    Ecto.Changeset.validate_change(changeset, field, fn ^field, id ->
      if Repo.exists?(from r in schema, where: r.id == ^id and r.story_id == ^story_id),
        do: [],
        else: [{field, message}]
    end)
  end

  ## Notices

  @doc "The notices of the boards (not expired), newest first, grouped by board id."
  def notices_by_board(boards) do
    ids = Enum.map(boards, & &1.id)
    now = DateTime.utc_now()

    from(n in Notice,
      where: n.board_id in ^ids and (is_nil(n.expires_at) or n.expires_at > ^now),
      order_by: [desc: n.inserted_at, desc: n.id],
      preload: :character
    )
    |> Repo.all()
    |> Enum.group_by(& &1.board_id)
  end

  def get_notice(%Story{id: story_id}, id) do
    case Integer.parse(to_string(id)) do
      {id, ""} ->
        Repo.get_by(Notice, id: id, story_id: story_id)

      _ ->
        nil
    end
  end

  def change_notice(%Notice{} = notice, attrs \\ %{}), do: Notice.changeset(notice, attrs)

  @doc """
  The characters the user can post notices as: their playable characters and,
  for the masters, the playable NPCs of the GDR.
  """
  def posting_characters(user, %Story{} = story),
    do: Characters.playable_characters(user, story)

  @doc """
  Pins a notice on a board as the character `attrs["character_id"]`, which
  the user must be able to act as (`Characters.can_act_as?/2`).
  """
  def post_notice(user, %Story{} = story, %Board{} = board, attrs) do
    with :ok <- check_enabled(story),
         :ok <- same_story(board, story),
         :ok <- authorize(accessible?(user, story, board)),
         {:ok, character} <- acting_character(user, story, attrs) do
      %Notice{
        board_id: board.id,
        story_id: story.id,
        character_id: character.id,
        user_id: user.id
      }
      |> Notice.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result(:notice)
    end
  end

  defp acting_character(user, story, attrs) do
    id = attrs["character_id"] || attrs[:character_id]

    with {id, ""} <- Integer.parse(to_string(id)),
         %Character{story_id: story_id} = character when story_id == story.id <-
           Characters.get_character(id),
         true <- Characters.can_act_as?(user, character) do
      {:ok, character}
    else
      _ -> {:error, :character_not_found}
    end
  end

  @doc "Removes a notice: its author or a master."
  def delete_notice(user, %Story{} = story, %Notice{} = notice) do
    with :ok <- same_story(notice, story),
         :ok <- authorize(notice.user_id == user.id or Stories.master?(user, story)) do
      notice |> Repo.delete() |> broadcast_result(:notice)
    end
  end

  @doc "Whether the user can remove the notice."
  def can_delete_notice?(user, story, %Notice{} = notice),
    do: notice.user_id == user.id or Stories.master?(user, story)

  ## Helpers

  defp check_enabled(story),
    do: if(enabled?(story), do: :ok, else: {:error, :module_disabled})

  defp check_master(user, story) do
    cond do
      not enabled?(story) -> {:error, :module_disabled}
      Stories.master?(user, story) -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp same_story(%{story_id: story_id}, %Story{id: story_id}), do: :ok
  defp same_story(_, _), do: {:error, :not_found}

  defp authorize(true), do: :ok
  defp authorize(_), do: {:error, :unauthorized}

  @doc "Where a board hangs: its room or zone name."
  def place_label(%Board{location: %Location{name: name}}), do: name
  def place_label(%Board{zone: %{name: name}}), do: "#{name} (zone)"
  def place_label(_), do: "—"

  def error_message(:module_disabled), do: "Bulletin boards are not enabled in this GDR."
  def error_message(:unauthorized), do: "You can't do that on this board."
  def error_message(:not_found), do: "That item does not exist in this GDR."
  def error_message(:character_not_found), do: "Pick one of your playable characters."
  def error_message(_), do: "Something went wrong."
end
