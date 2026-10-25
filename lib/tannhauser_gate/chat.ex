defmodule TannhauserGate.Chat do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  Real time, per-location chat. Players speak through one of their characters
  (in character, or OFF game), masters narrate and set the room status, and
  everyone who can play rolls dice with the GDR dice system.

  Old entries are moved to `archived_messages` by `TannhauserGate.Chat.Archiver`
  after the GDR archive age; `search_log/3` covers both tables.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Bookings
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Chat.{ArchivedMessage, Message}
  alias TannhauserGate.Dice
  alias TannhauserGate.Experience
  alias TannhauserGate.Repo
  alias TannhauserGate.Sanctions
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Location

  @pubsub TannhauserGate.PubSub
  @narrator "Narrator"
  @preloads [:character, :user, :recipient_character]

  def topic(location_id), do: "room:#{location_id}"

  @doc "The topic of the whispers of a room sent by or to a user."
  def whisper_topic(location_id, user_id), do: "room:#{location_id}:whispers:#{user_id}"

  @doc "The topic carrying every whisper of a room (masters)."
  def masters_whisper_topic(location_id), do: "room:#{location_id}:whispers:masters"

  @doc """
  Subscribes to the public entries of a room. Whispers are never broadcast
  there: see `subscribe_whispers/2`.
  """
  def subscribe(location_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(location_id))

  @doc """
  Subscribes to the whispers of a room a viewer may read: `:all` (masters)
  or a user (those they sent or that were sent to their characters).
  """
  def subscribe_whispers(location_id, :all),
    do: Phoenix.PubSub.subscribe(@pubsub, masters_whisper_topic(location_id))

  def subscribe_whispers(location_id, %User{id: user_id}),
    do: Phoenix.PubSub.subscribe(@pubsub, whisper_topic(location_id, user_id))

  @doc """
  Whether a viewer (`:all` for masters, a user, or nil) may read an entry:
  whispers only for their sender, the owner of their recipient and masters.
  """
  def visible?(%{kind: "whisper"}, :all), do: true

  def visible?(%{kind: "whisper"} = message, %User{id: user_id}) do
    message.user_id == user_id or
      match?(%Character{user_id: ^user_id}, message.recipient_character)
  end

  def visible?(%{kind: "whisper"}, _viewer), do: false
  def visible?(_message, _viewer), do: true

  @doc "The name shown for entries without a character."
  def narrator, do: @narrator

  @doc "The name of who posted an entry: its character, or the Narrator."
  def speaker_name(%{character: %Character{name: name}}), do: name
  def speaker_name(%{speaker_name: name}) when is_binary(name), do: name
  def speaker_name(_), do: @narrator

  ## Reading

  @doc """
  Returns the latest messages of a location, oldest first.

  Accepts a limit (default 100) or options: `:limit`, `:before` (a message,
  to page back to older entries) and `:viewer` (see `visible?/2`: `:all`
  includes every whisper, a user those they may read; by default whispers
  are excluded).
  """
  def list_messages(location_id, opts \\ [])

  def list_messages(location_id, limit) when is_integer(limit),
    do: list_messages(location_id, limit: limit)

  def list_messages(location_id, opts) do
    limit = Keyword.get(opts, :limit, 100)

    from(m in Message,
      where: m.location_id == ^location_id,
      order_by: [desc: m.inserted_at, desc: m.id],
      limit: ^limit,
      preload: ^@preloads
    )
    |> before(opts[:before])
    |> visible_to(opts[:viewer])
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  A page of messages (oldest first) and whether older ones exist. See
  `list_messages/2` for the options (`:limit` defaults to 50).
  """
  def page_messages(location_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    messages = list_messages(location_id, Keyword.put(opts, :limit, limit + 1))

    if length(messages) > limit,
      do: {tl(messages), true},
      else: {messages, false}
  end

  defp visible_to(query, :all), do: query

  defp visible_to(query, %User{id: user_id}) do
    from m in query,
      left_join: r in Character,
      on: r.id == m.recipient_character_id,
      where: m.kind != "whisper" or m.user_id == ^user_id or r.user_id == ^user_id
  end

  defp visible_to(query, _viewer), do: where(query, [m], m.kind != "whisper")

  defp before(query, nil), do: query

  defp before(query, %{id: id, inserted_at: at}) do
    from m in query, where: m.inserted_at < ^at or (m.inserted_at == ^at and m.id < ^id)
  end

  def get_message!(id), do: Message |> Repo.get!(id) |> Repo.preload(@preloads)

  @doc "Gets a message of a location, or nil."
  def get_location_message(location_id, id) do
    Repo.one(
      from m in Message,
        where: m.id == ^id and m.location_id == ^location_id,
        preload: ^@preloads
    )
  end

  ## Posting

  @doc """
  Posts a message in a location speaking as `character_id`.

  `"kind"` is `"speech"` (default, in character), `"ooc"` (OFF game) or,
  with the chat roleplay module, `"whisper"` (in character, to the approved
  character `"recipient_character_id"` of the GDR). In character the user
  must be able to act as the character (`Characters.can_act_as?/2`); OFF
  game it is enough to control it (own it, or master its GDR for NPCs),
  whatever its approval. The character must belong to the location's story
  and the user must be allowed in the location (`Bookings.can_access?/3`).

  With the chat roleplay module in-character entries take an optional
  `"tag"` and must respect the GDR length limits (`chat_min_length`,
  `chat_max_length`). With the automatic XP module an in-character speech
  of a player character may award XP (`Experience.award_chat_activity/4`).
  """
  def create_message(%User{} = user, %Location{} = location, attrs) do
    character_id = attrs["character_id"] || attrs[:character_id]
    body = attrs["body"] || attrs[:body]
    kind = attrs["kind"] || attrs[:kind] || "speech"
    story = Stories.get_story(location.story_id)
    rp? = Stories.module_enabled?(story, :chat_rp)
    kinds = if rp?, do: ["speech", "ooc", "whisper"], else: ["speech", "ooc"]

    with :ok <- Sanctions.check_not_muted(user, story),
         true <- kind in kinds || {:error, :invalid_kind},
         {:ok, character} <- acting_character(user, location, character_id, kind),
         {:ok, recipient} <- whisper_recipient(kind, location, character, attrs),
         {:ok, message} <-
           insert(location, user, character, kind, entry_attrs(rp?, kind, body, attrs),
             recipient: recipient,
             limits: rp? && {story.chat_min_length, story.chat_max_length}
           ) do
      maybe_award_xp(story, character, message)
      {:ok, message}
    end
  end

  defp entry_attrs(rp?, kind, body, attrs) do
    tag = attrs["tag"] || attrs[:tag]

    if rp? and Message.in_character_kind?(kind),
      do: %{body: body, tag: tag},
      else: %{body: body}
  end

  defp whisper_recipient("whisper", location, character, attrs) do
    case fetch_character(attrs["recipient_character_id"] || attrs[:recipient_character_id]) do
      %Character{story_id: story_id, approval_status: "approved"} = recipient
      when story_id == location.story_id ->
        cond do
          recipient.id == character.id ->
            {:error, :whisper_self}

          Characters.alts_blocked?(:block_alt_whispers, character, recipient) ->
            {:error, :alt_blocked}

          true ->
            {:ok, recipient}
        end

      _ ->
        {:error, :no_recipient}
    end
  end

  defp whisper_recipient(_kind, _location, _character, _attrs), do: {:ok, nil}

  defp maybe_award_xp(story, %Character{is_npc: false} = character, %Message{kind: "speech"} = m) do
    _ = Experience.award_chat_activity(story, character, String.length(m.body))
    :ok
  end

  defp maybe_award_xp(_story, _character, _message), do: :ok

  @doc "Posts a master narration (shown as the Narrator). Masters only."
  def narrate(%User{} = user, %Location{} = location, body) do
    with :ok <- check_master(user, location) do
      insert(location, user, nil, "narration", %{body: body})
    end
  end

  @doc """
  Sets the current status of a room (shown in its header) and logs it in the
  chat. A blank text clears the status. Masters only. Returns
  `{:ok, location, message}`.
  """
  def set_room_status(%User{} = user, %Location{} = location, text) do
    text = text |> to_string() |> String.trim()
    status = if text == "", do: nil, else: text
    body = status || "The room status was cleared."

    with :ok <- check_master(user, location),
         {:ok, location} <- location |> Location.status_changeset(status) |> Repo.update(),
         {:ok, message} <- insert(location, user, nil, "status", %{body: body}) do
      broadcast(location.id, {:room_status, location})
      {:ok, location, message}
    end
  end

  @doc """
  Rolls dice as a character and posts the result as a dice entry.

  `attrs` carries `"character_id"` and the roll request understood by
  `TannhauserGate.Dice.roll/3` (`"items"`, `"modifier"`, `"difficulty"`,
  `"expression"`, `"label"`). Only characters that can play can roll (NPCs
  included, for masters). `opts` are passed to `Dice.roll/3` (e.g. `:rng`).
  """
  def roll_dice(%User{} = user, %Location{} = location, attrs, opts \\ []) do
    character_id = attrs["character_id"] || attrs[:character_id]

    with :ok <- Sanctions.check_not_muted(user, location.story_id),
         {:ok, character} <- acting_character(user, location, character_id, "dice"),
         {:ok, result} <- Dice.roll(character, attrs, opts) do
      insert(location, user, character, "dice", %{body: dice_body(result)}, data: result)
    end
  end

  @doc """
  Spends the GDR reroll tracker of the rolling character to reroll some failed
  dice of a pool roll once (see `TannhauserGate.Dice.reroll/4`). Allowed to
  whoever rolled and to the masters. Updates the entry and broadcasts it.
  """
  def reroll(user, message, indexes \\ nil, opts \\ [])

  def reroll(%User{} = user, %Message{kind: "dice"} = message, indexes, opts) do
    Repo.transaction(fn ->
      Message
      |> where([m], m.id == ^message.id)
      |> lock("FOR UPDATE")
      |> Repo.one!()
      |> Repo.preload(@preloads)
      |> do_reroll(user, indexes, opts)
    end)
    |> case do
      {:ok, message} ->
        broadcast(message.location_id, {:updated_message, message})
        {:ok, message}

      error ->
        error
    end
  end

  def reroll(_user, _message, _indexes, _opts), do: {:error, :not_a_pool}

  defp do_reroll(message, user, indexes, opts) do
    location = Stories.get_location!(message.location_id)

    with true <- rerolls?(user, message, location) || {:error, :unauthorized},
         %Character{} = character <- message.character || {:error, :unauthorized},
         {:ok, result} <- Dice.reroll(character, message.data, indexes, opts),
         {:ok, updated} <-
           message
           |> Ecto.Changeset.change(data: result, body: dice_body(result))
           |> Repo.update() do
      updated
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp rerolls?(user, message, location),
    do: message.user_id == user.id or Stories.master?(user, location.story)

  defp dice_body(%{"label" => label, "summary" => summary}) when is_binary(label),
    do: "#{label}: #{summary}"

  defp dice_body(%{"summary" => summary}), do: summary

  defp acting_character(user, location, character_id, kind) do
    with %Character{} = character <- fetch_character(character_id),
         true <- character.story_id == location.story_id || {:error, :wrong_story},
         true <- controls?(user, character) || {:error, :unauthorized},
         true <-
           kind == "ooc" || Characters.can_act_as?(user, character) || {:error, :cannot_play},
         true <- Bookings.can_access?(user, location) || {:error, :private} do
      {:ok, character}
    else
      nil -> {:error, :character_not_found}
      {:error, _} = error -> error
    end
  end

  defp check_master(user, location) do
    if Stories.master?(user, Stories.get_story(location.story_id)),
      do: :ok,
      else: {:error, :not_master}
  end

  defp insert(location, user, character, kind, attrs, opts \\ []) do
    recipient = opts[:recipient]
    {min, max} = opts[:limits] || {nil, nil}

    %Message{
      location_id: location.id,
      character_id: character && character.id,
      recipient_character_id: recipient && recipient.id,
      user_id: user.id,
      kind: kind,
      data: opts[:data]
    }
    |> Message.changeset(attrs)
    |> Message.validate_limits(min, max)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = %{message | character: character, user: user, recipient_character: recipient}
        broadcast_message(message, {:new_message, message})
        {:ok, message}

      error ->
        error
    end
  end

  # Whispers only go to the topics of their sender, of the owner of their
  # recipient and of the masters, never to the public room topic.
  defp broadcast_message(%Message{kind: "whisper"} = message, payload) do
    owner = message.recipient_character && message.recipient_character.user_id

    for user_id <- Enum.uniq(Enum.reject([message.user_id, owner], &is_nil/1)) do
      Phoenix.PubSub.broadcast(@pubsub, whisper_topic(message.location_id, user_id), payload)
    end

    Phoenix.PubSub.broadcast(@pubsub, masters_whisper_topic(message.location_id), payload)
  end

  defp broadcast_message(message, payload), do: broadcast(message.location_id, payload)

  ## Moderation

  @doc """
  Returns the latest `limit` messages posted in any room of a story, newest
  first (used by the master moderation tools).
  """
  def list_story_messages(story_id, limit \\ 50) do
    Repo.all(
      from m in Message,
        join: l in Location,
        on: l.id == m.location_id,
        where: l.story_id == ^story_id,
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^limit,
        preload: [:character, :user, :location, :recipient_character]
    )
  end

  @doc "Gets a message of the given story, or `nil`."
  def get_story_message(story_id, id) do
    Repo.one(
      from m in Message,
        join: l in Location,
        on: l.id == m.location_id,
        where: m.id == ^id and l.story_id == ^story_id
    )
  end

  @dice_errors [
    :unknown_item,
    :no_reroll,
    :not_a_pool,
    :already_rerolled,
    :nothing_to_reroll,
    :invalid_dice,
    :not_enough,
    :not_found
  ]

  @doc "A human readable message for the chat errors."
  def error_message(:cannot_play),
    do:
      dgettext(
        "domain",
        "That character cannot play yet: it must be approved and in a playable state."
      )

  def error_message(:private),
    do: dgettext("domain", "This private location is not booked for you right now.")

  def error_message(:invalid_kind), do: dgettext("domain", "That kind of message does not exist.")

  def error_message(:alt_blocked),
    do:
      dgettext(
        "domain",
        "This GDR does not allow whispers between characters of the same player."
      )

  def error_message(:no_recipient),
    do: dgettext("domain", "Choose an approved character of this GDR to whisper to.")

  def error_message(:whisper_self), do: dgettext("domain", "You cannot whisper to yourself.")
  def error_message(:not_master), do: dgettext("domain", "Only the GDR masters can do that.")

  def error_message(:muted),
    do: dgettext("domain", "You are muted in this GDR: you cannot post right now.")

  def error_message(%Ecto.Changeset{}), do: dgettext("domain", "The message could not be posted.")
  def error_message(reason) when reason in @dice_errors, do: Dice.error_message(reason)
  def error_message(reason) when is_binary(reason), do: reason

  def error_message(_),
    do: dgettext("domain", "You can only speak as one of your characters in this story.")

  @doc """
  Deletes a chat entry of the story on behalf of a moderator
  (`Stories.can?(user, story, :can_moderate)`).
  """
  def delete_message(%User{} = user, %Message{} = message) do
    story = message.location_id |> Stories.get_location!() |> Map.fetch!(:story)

    if Stories.can?(user, story, :can_moderate),
      do: delete_message(message),
      else: {:error, :unauthorized}
  end

  def delete_message(%Message{} = message) do
    with {:ok, message} <- Repo.delete(message) do
      # Only the id travels: a deleted whisper must not leak its content.
      broadcast(
        message.location_id,
        {:deleted_message, %Message{id: message.id, location_id: message.location_id}}
      )

      {:ok, message}
    end
  end

  @doc """
  Returns a map of `location_id => message count`.
  """
  def count_messages_by_location do
    from(m in Message, group_by: m.location_id, select: {m.location_id, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  ## History

  @doc """
  Moves every message older than the archive age of its GDR
  (`archive_after_days`; nil never archives) into `archived_messages`.
  Returns the number of archived messages.
  """
  def archive_old_messages(now \\ DateTime.utc_now()) do
    now = now |> DateTime.truncate(:second) |> DateTime.to_naive()

    %{num_rows: count} =
      Repo.query!(
        """
        WITH moved AS (
          DELETE FROM messages m
          USING locations l, stories s
          WHERE m.location_id = l.id AND l.story_id = s.id
            AND s.archive_after_days IS NOT NULL
            AND m.inserted_at < $1::timestamp - make_interval(days => s.archive_after_days)
          RETURNING m.location_id, m.character_id, m.user_id, m.kind, m.body, m.data,
                    m.tag, m.recipient_character_id, m.inserted_at
        )
        INSERT INTO archived_messages
          (location_id, character_id, user_id, kind, body, data, tag, recipient_character_id,
           recipient_name, speaker_name, inserted_at, archived_at)
        SELECT moved.location_id, moved.character_id, moved.user_id, moved.kind, moved.body,
               moved.data, moved.tag, moved.recipient_character_id, rc.name,
               COALESCE(c.name, $2), moved.inserted_at, $1::timestamp
        FROM moved
        LEFT JOIN characters c ON c.id = moved.character_id
        LEFT JOIN characters rc ON rc.id = moved.recipient_character_id
        """,
        [now, @narrator]
      )

    count
  end

  @doc """
  The chat log of a story for the masters: live and archived entries, newest
  first. Filters (string keys): `"location_id"`, `"from"` and `"to"` (ISO
  dates, inclusive, UTC).
  """
  def search_log(story_id, filters \\ %{}, limit \\ 200) do
    live =
      from(m in Message,
        join: l in Location,
        on: l.id == m.location_id,
        where: l.story_id == ^story_id,
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^limit,
        preload: [:character, :user, :location, :recipient_character]
      )
      |> log_filters(filters)
      |> Repo.all()
      |> Enum.map(&log_entry(&1, false))

    archived =
      from(m in ArchivedMessage,
        join: l in Location,
        on: l.id == m.location_id,
        where: l.story_id == ^story_id,
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: ^limit,
        preload: [:user, :location]
      )
      |> log_filters(filters)
      |> Repo.all()
      |> Enum.map(&log_entry(&1, true))

    (live ++ archived)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  defp log_entry(message, archived?) do
    %{
      id: "#{if archived?, do: "a", else: "m"}-#{message.id}",
      archived?: archived?,
      kind: message.kind,
      body: message.body,
      data: message.data,
      tag: message.tag,
      recipient: recipient_name(message),
      speaker: speaker_name(message),
      username: message.user && message.user.username,
      location: message.location,
      inserted_at: message.inserted_at
    }
  end

  defp recipient_name(%ArchivedMessage{recipient_name: name}), do: name
  defp recipient_name(%Message{recipient_character: %Character{name: name}}), do: name
  defp recipient_name(_), do: nil

  defp log_filters(query, filters) do
    Enum.reduce(filters, query, &log_filter/2)
  end

  defp log_filter({"location_id", id}, query) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> from m in query, where: m.location_id == ^id
      _ -> query
    end
  end

  defp log_filter({"from", date}, query) do
    case parse_date(date) do
      %Date{} = date -> from m in query, where: m.inserted_at >= ^start_of(date)
      nil -> query
    end
  end

  defp log_filter({"to", date}, query) do
    case parse_date(date) do
      %Date{} = date -> from m in query, where: m.inserted_at < ^start_of(Date.add(date, 1))
      nil -> query
    end
  end

  defp log_filter(_filter, query), do: query

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp start_of(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  ## Helpers

  defp controls?(user, %Character{is_npc: true} = character),
    do: Stories.master?(user, Stories.get_story(character.story_id))

  defp controls?(%User{id: id}, %Character{user_id: id}), do: true
  defp controls?(_, _), do: false

  defp fetch_character(nil), do: nil
  defp fetch_character(""), do: nil

  defp fetch_character(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> Repo.get(Character, int)
      _ -> nil
    end
  end

  defp broadcast(location_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(location_id), message)
  end
end
