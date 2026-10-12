defmodule TannhauserGate.Mailbox do
  @moduledoc """
  The per-GDR mailbox: messages between characters.

  A user's mailbox gathers the mail of every character they own in the GDR;
  masters also share the mail of the NPCs and of "The masters" (a nil
  recipient, or a sender flagged `from_masters`). Messages are sent as one
  of the characters the user can act as (masters may also sign as
  "The masters"):

    * masters can write to any character of the GDR;
    * players can write to approved characters;
    * anyone can write to "The masters".

  Reading is never gated: a character that cannot play can still read its
  mail. Each side (inbox and sent) deletes messages independently.

  Every change is broadcast as `{:mailbox, event, message}` on `topic/1`
  (`event` is `:received`, `:read` or `:deleted`).
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Mailbox.Message
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  @pubsub TannhauserGate.PubSub
  @masters "masters"
  @masters_name "The masters"

  def topic(story_id), do: "mailbox:story:#{story_id}"

  def subscribe(story_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(story_id))

  defp broadcast(story_id, event, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(story_id), {:mailbox, event, message})
  end

  @doc "The value standing for \"The masters\" in sender and recipient fields."
  def masters, do: @masters

  ## Identity

  @doc """
  The characters whose mail the user reads in the story: their own player
  characters (whatever their status) and, for masters, the NPCs.
  """
  def mailbox_characters(%User{} = user, %Story{} = story) do
    own = Characters.list_user_characters(user, story.id)
    if Stories.master?(user, story), do: own ++ Characters.list_npcs(story.id), else: own
  end

  @doc """
  The mailbox identity of the user in the story: `%{character_ids: [...],
  master?: boolean}`. Everything else accepts it in place of the user.
  """
  def identity(%User{} = user, %Story{} = story) do
    %{
      character_ids: user |> mailbox_characters(story) |> Enum.map(& &1.id),
      master?: Stories.master?(user, story)
    }
  end

  defp inbox_query(story_id, %{character_ids: ids, master?: master?}) do
    from m in Message,
      where:
        m.story_id == ^story_id and is_nil(m.recipient_deleted_at) and
          (m.recipient_character_id in ^ids or
             (is_nil(m.recipient_character_id) and ^master?))
  end

  defp sent_query(story_id, %{character_ids: ids, master?: master?}) do
    from m in Message,
      where:
        m.story_id == ^story_id and is_nil(m.sender_deleted_at) and
          (m.sender_character_id in ^ids or (m.from_masters and ^master?))
  end

  @doc "Whether the message is in the inbox of the identity."
  def in_inbox?(%{character_ids: ids, master?: master?}, %Message{} = message) do
    case message.recipient_character_id do
      nil -> master?
      id -> id in ids
    end
  end

  @doc "Whether the message was sent by the identity."
  def sent_by?(%{character_ids: ids, master?: master?}, %Message{} = message) do
    if message.from_masters, do: master?, else: message.sender_character_id in ids
  end

  ## Listing

  @doc "The received messages of the user in the story, newest first."
  def list_inbox(%User{} = user, %Story{} = story) do
    story.id
    |> inbox_query(identity(user, story))
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> preload([:sender_character, :recipient_character])
    |> Repo.all()
  end

  @doc "The messages sent by the user's characters in the story, newest first."
  def list_sent(%User{} = user, %Story{} = story) do
    story.id
    |> sent_query(identity(user, story))
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> preload([:sender_character, :recipient_character])
    |> Repo.all()
  end

  @doc "The number of unread received messages of the user (or identity) in the story."
  def unread_count(%User{} = user, %Story{} = story),
    do: unread_count(story.id, identity(user, story))

  def unread_count(story_id, identity) do
    story_id
    |> inbox_query(identity)
    |> where([m], is_nil(m.read_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  A message of the story the user can see (on either side, not deleted on
  that side), or `nil`.
  """
  def get_message(%User{} = user, %Story{} = story, id) do
    identity = identity(user, story)

    with id when is_integer(id) <- to_id(id),
         %Message{} = message <-
           Repo.one(
             from m in Message,
               where: m.id == ^id and m.story_id == ^story.id,
               preload: [:sender_character, :recipient_character]
           ),
         true <- visible?(identity, message) do
      message
    else
      _ -> nil
    end
  end

  defp visible?(identity, message) do
    (in_inbox?(identity, message) and is_nil(message.recipient_deleted_at)) or
      (sent_by?(identity, message) and is_nil(message.sender_deleted_at))
  end

  @doc "The display name of the recipient."
  def recipient_name(%Message{recipient_character: %Character{name: name}}), do: name
  def recipient_name(%Message{recipient_character_id: nil}), do: @masters_name
  def recipient_name(_), do: "unknown"

  ## Reading and deleting

  @doc "Marks a received message as read (no-op for the sender side or when already read)."
  def mark_read(%User{} = user, %Story{} = story, %Message{read_at: nil} = message) do
    if in_inbox?(identity(user, story), message) do
      {:ok, message} =
        message
        |> Changeset.change(read_at: DateTime.utc_now(:second))
        |> Repo.update()

      broadcast(story.id, :read, message)
      {:ok, message}
    else
      {:ok, message}
    end
  end

  def mark_read(_user, _story, %Message{} = message), do: {:ok, message}

  @doc """
  Deletes the given messages from one side (`:inbox` or `:sent`) of the
  user's mailbox; the other side keeps them. Returns the number deleted.
  """
  def delete_messages(%User{} = user, %Story{} = story, ids, side) when side in [:inbox, :sent] do
    ids = ids |> List.wrap() |> Enum.map(&to_id/1) |> Enum.filter(&is_integer/1)
    identity = identity(user, story)
    now = DateTime.utc_now(:second)

    {query, field} =
      case side do
        :inbox -> {inbox_query(story.id, identity), :recipient_deleted_at}
        :sent -> {sent_query(story.id, identity), :sender_deleted_at}
      end

    {count, _} =
      query
      |> where([m], m.id in ^ids)
      |> Repo.update_all(set: [{field, now}])

    if count > 0, do: broadcast(story.id, :deleted, nil)
    count
  end

  ## Sending

  @doc """
  The characters (and "The masters", for masters) the user can sign as,
  as `{label, value}` select options.
  """
  def sender_options(%User{} = user, %Story{} = story) do
    characters =
      user
      |> Characters.playable_characters(story)
      |> Enum.map(&{character_label(&1), to_string(&1.id)})

    if Stories.master?(user, story),
      do: characters ++ [{@masters_name, @masters}],
      else: characters
  end

  @doc """
  The recipients the user can write to, as `{label, value}` select options:
  "The masters", then any character (masters) or the approved ones (players).
  """
  def recipient_options(%User{} = user, %Story{} = story) do
    characters =
      story
      |> recipient_characters(Stories.master?(user, story))
      |> Enum.map(&{character_label(&1), to_string(&1.id)})

    [{@masters_name, @masters} | characters]
  end

  defp recipient_characters(story, true), do: Characters.list_story_characters(story.id)

  defp recipient_characters(story, false),
    do: Characters.list_story_characters(story.id, %{"approval_status" => "approved"})

  defp character_label(%Character{is_npc: true, name: name}), do: "#{name} (NPC)"
  defp character_label(%Character{name: name}), do: name

  def change_message(attrs \\ %{}), do: Message.changeset(%Message{}, attrs)

  @doc """
  Sends a message. `attrs` (string keys): `"sender"` and `"recipient"`
  (a character id or `"masters"`), `"subject"`, `"body"` and the optional
  `"reply_to_id"`. Returns `{:ok, message}` or `{:error, changeset}`.
  """
  def send_message(%User{} = user, %Story{} = story, attrs) do
    master? = Stories.master?(user, story)

    %Message{story_id: story.id, sender_user_id: user.id}
    |> Message.changeset(attrs)
    |> put_sender(user, story, master?)
    |> put_recipient(story, master?)
    |> validate_not_to_self()
    |> put_reply_to(story, attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = Repo.preload(message, [:sender_character, :recipient_character])
        broadcast(story.id, :received, message)
        {:ok, message}

      error ->
        error
    end
  end

  defp put_sender(changeset, user, story, master?) do
    case Changeset.get_change(changeset, :sender) do
      nil ->
        changeset

      @masters when master? ->
        Changeset.change(changeset, from_masters: true, sender_name: @masters_name)

      value ->
        case find_character(user |> Characters.playable_characters(story), value) do
          %Character{} = c ->
            Changeset.change(changeset, sender_character_id: c.id, sender_name: c.name)

          nil ->
            Changeset.add_error(changeset, :sender, "is not a character you can play")
        end
    end
  end

  defp put_recipient(changeset, story, master?) do
    case Changeset.get_change(changeset, :recipient) do
      nil ->
        changeset

      @masters ->
        changeset

      value ->
        case find_character(recipient_characters(story, master?), value) do
          %Character{} = c -> Changeset.put_change(changeset, :recipient_character_id, c.id)
          nil -> Changeset.add_error(changeset, :recipient, "is not a character you can write to")
        end
    end
  end

  defp validate_not_to_self(changeset) do
    if Changeset.get_field(changeset, :from_masters) and
         Changeset.get_change(changeset, :recipient) == @masters,
       do: Changeset.add_error(changeset, :recipient, "the masters cannot write to themselves"),
       else: changeset
  end

  defp put_reply_to(changeset, story, attrs) do
    with id when is_integer(id) <- to_id(attrs["reply_to_id"]),
         true <- Repo.exists?(from m in Message, where: m.id == ^id and m.story_id == ^story.id) do
      Changeset.put_change(changeset, :reply_to_id, id)
    else
      _ -> changeset
    end
  end

  defp find_character(characters, value) do
    id = to_id(value)
    Enum.find(characters, &(&1.id == id))
  end

  @doc """
  The form defaults to reply to a message: from the character it was sent to,
  to its sender, with a "Re:" subject.
  """
  def reply_attrs(%User{} = user, %Story{} = story, %Message{} = message) do
    senders = user |> sender_options(story) |> Enum.map(&elem(&1, 1))

    sender =
      case message.recipient_character_id do
        nil -> @masters
        id -> to_string(id)
      end

    recipient =
      cond do
        message.from_masters -> @masters
        message.sender_character_id -> to_string(message.sender_character_id)
        true -> ""
      end

    subject =
      if String.starts_with?(message.subject, "Re: "),
        do: message.subject,
        else: "Re: " <> message.subject

    %{
      "sender" => if(sender in senders, do: sender, else: List.first(senders)),
      "recipient" => recipient,
      "subject" => subject,
      "body" => "",
      "reply_to_id" => to_string(message.id)
    }
  end

  defp to_id(id) when is_integer(id), do: id

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_id(_), do: nil
end
