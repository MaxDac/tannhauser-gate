defmodule TannhauserGate.Chat do
  @moduledoc """
  Real time, per-location chat. Players speak through one of their characters.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Chat.Message
  alias TannhauserGate.Repo
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

  The character must belong to the user and to the location's story.
  """
  def create_message(%User{} = user, %Location{} = location, attrs) do
    character_id = attrs["character_id"] || attrs[:character_id]
    body = attrs["body"] || attrs[:body]

    with %Character{} = character <- fetch_character(character_id),
         true <- character.user_id == user.id || {:error, :unauthorized},
         true <- character.story_id == location.story_id || {:error, :wrong_story} do
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
