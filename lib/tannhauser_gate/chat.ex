defmodule TannhauserGate.Chat do
  @moduledoc """
  Real time, per-location chat. Players speak through one of their characters.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Chat.Message
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Location

  @pubsub TannhauserGate.PubSub

  def topic(location_id), do: "room:#{location_id}"

  def subscribe(location_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(location_id))

  @doc """
  Returns the latest `limit` messages of a location, oldest first.
  """
  def list_messages(location_id, limit \\ 100) do
    from(m in Message,
      where: m.location_id == ^location_id,
      order_by: [desc: m.inserted_at, desc: m.id],
      limit: ^limit,
      preload: [:character, :user]
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  def get_message!(id), do: Message |> Repo.get!(id) |> Repo.preload([:character, :user])

  @doc """
  Posts a message in a location speaking as `character_id`.

  The user must be able to act as the character (`Characters.can_act_as?/2`:
  their own approved, playable character, or a playable NPC of a GDR they
  master) and the character must belong to the location's story.
  """
  def create_message(%User{} = user, %Location{} = location, attrs) do
    character_id = attrs["character_id"] || attrs[:character_id]
    body = attrs["body"] || attrs[:body]

    with %Character{} = character <- fetch_character(character_id),
         true <- character.story_id == location.story_id || {:error, :wrong_story},
         true <- controls?(user, character) || {:error, :unauthorized},
         true <- Characters.can_act_as?(user, character) || {:error, :cannot_play} do
      %Message{location_id: location.id, character_id: character.id, user_id: user.id}
      |> Message.changeset(%{body: body})
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          message = %{message | character: character, user: user}
          broadcast(location.id, {:new_message, message})
          {:ok, message}

        error ->
          error
      end
    else
      nil -> {:error, :character_not_found}
      {:error, _} = error -> error
    end
  end

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

  @doc "A human readable message for `create_message/3` errors."
  def error_message(:cannot_play),
    do: "That character cannot play yet: it must be approved and in a playable state."

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
