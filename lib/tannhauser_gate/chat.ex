defmodule TannhauserGate.Chat do
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
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Location

  @pubsub TannhauserGate.PubSub
  @narrator "Narrator"

  def topic(location_id), do: "room:#{location_id}"

  def subscribe(location_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(location_id))

  @doc "The name shown for entries without a character."
  def narrator, do: @narrator

  @doc "The name of who posted an entry: its character, or the Narrator."
  def speaker_name(%{character: %Character{name: name}}), do: name
  def speaker_name(%{speaker_name: name}) when is_binary(name), do: name
  def speaker_name(_), do: @narrator

  ## Reading

  @doc """
  Returns the latest messages of a location, oldest first.

  Accepts a limit (default 100) or options: `:limit` and `:before` (a message,
  to page back to older entries).
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
      preload: [:character, :user]
    )
    |> before(opts[:before])
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

  defp before(query, nil), do: query

  defp before(query, %{id: id, inserted_at: at}) do
    from m in query, where: m.inserted_at < ^at or (m.inserted_at == ^at and m.id < ^id)
  end

  def get_message!(id), do: Message |> Repo.get!(id) |> Repo.preload([:character, :user])

  @doc "Gets a message of a location, or nil."
  def get_location_message(location_id, id) do
    Repo.one(
      from m in Message,
        where: m.id == ^id and m.location_id == ^location_id,
        preload: [:character, :user]
    )
  end

  ## Posting

  @doc """
  Posts a message in a location speaking as `character_id`.

  `"kind"` is `"speech"` (default, in character) or `"ooc"` (OFF game). In
  character the user must be able to act as the character
  (`Characters.can_act_as?/2`); OFF game it is enough to control it (own it,
  or master its GDR for NPCs), whatever its approval. The character must
  belong to the location's story and the user must be allowed in the location
  (`Bookings.can_access?/3`).
  """
  def create_message(%User{} = user, %Location{} = location, attrs) do
    character_id = attrs["character_id"] || attrs[:character_id]
    body = attrs["body"] || attrs[:body]
    kind = attrs["kind"] || attrs[:kind] || "speech"

    with true <- kind in ["speech", "ooc"] || {:error, :invalid_kind},
         {:ok, character} <- acting_character(user, location, character_id, kind) do
      insert(location, user, character, kind, %{body: body})
    end
  end

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

    with {:ok, character} <- acting_character(user, location, character_id, "dice"),
         {:ok, result} <- Dice.roll(character, attrs, opts) do
      insert(location, user, character, "dice", %{body: dice_body(result)}, result)
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
      |> Repo.preload([:character, :user])
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

  defp insert(location, user, character, kind, attrs, data \\ nil) do
    %Message{
      location_id: location.id,
      character_id: character && character.id,
      user_id: user.id,
      kind: kind,
      data: data
    }
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = %{message | character: character, user: user}
        broadcast(location.id, {:new_message, message})
        {:ok, message}

      error ->
        error
    end
  end

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
        preload: [:character, :user, :location]
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
    do: "That character cannot play yet: it must be approved and in a playable state."

  def error_message(:private), do: "This private location is not booked for you right now."
  def error_message(:invalid_kind), do: "That kind of message does not exist."
  def error_message(:not_master), do: "Only the GDR masters can do that."
  def error_message(%Ecto.Changeset{}), do: "The message could not be posted."
  def error_message(reason) when reason in @dice_errors, do: Dice.error_message(reason)
  def error_message(reason) when is_binary(reason), do: reason
  def error_message(_), do: "You can only speak as one of your characters in this story."

  def delete_message(%Message{} = message) do
    with {:ok, message} <- Repo.delete(message) do
      broadcast(message.location_id, {:deleted_message, message})
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
                    m.inserted_at
        )
        INSERT INTO archived_messages
          (location_id, character_id, user_id, kind, body, data, speaker_name, inserted_at,
           archived_at)
        SELECT moved.location_id, moved.character_id, moved.user_id, moved.kind, moved.body,
               moved.data, COALESCE(c.name, $2), moved.inserted_at, $1::timestamp
        FROM moved LEFT JOIN characters c ON c.id = moved.character_id
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
        preload: [:character, :user, :location]
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
      speaker: speaker_name(message),
      username: message.user && message.user.username,
      location: message.location,
      inserted_at: message.inserted_at
    }
  end

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
