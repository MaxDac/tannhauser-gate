defmodule TannhauserGateWeb.GdrPresence do
  @moduledoc """
  Tracks the users online in a GDR, with the character they play and the
  location they are in, and keeps the `:online` assign (shown in the
  layout) up to date.

  Mounted with `on_mount {TannhauserGateWeb.GdrPresence, :track}` after
  `UserAuth`'s `:load_story`; rooms call `enter_location/2`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias TannhauserGate.{Characters, Guilds, Stories}
  alias TannhauserGateWeb.Presence

  def topic(story_id), do: "presence:story:#{story_id}"

  def on_mount(:track, _params, _session, socket) do
    story = socket.assigns.current_story
    user = socket.assigns.current_user
    socket = assign(socket, :last_location, Stories.last_location(user, story.id))

    if connected?(socket) do
      topic = topic(story.id)
      character = Characters.get_user_story_character(user, story.id)

      {:ok, _} =
        Presence.track(self(), topic, to_string(user.id), %{
          user_id: user.id,
          username: user.username,
          character_id: character && character.id,
          character_name: character && character.name,
          guilds: if(character, do: Guilds.public_guild_names(character), else: []),
          location_id: nil,
          location_name: nil,
          location_private: false,
          online_at: System.system_time(:millisecond)
        })

      Phoenix.PubSub.subscribe(TannhauserGate.PubSub, topic)

      {:cont,
       socket
       |> assign(:online, list_online(story.id))
       |> attach_hook(:gdr_presence, :handle_info, &handle_info/2)}
    else
      {:cont, assign(socket, :online, [])}
    end
  end

  defp handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:halt, assign(socket, :online, list_online(socket.assigns.current_story.id))}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  @doc """
  Records that the current LiveView user is in a location: updates their
  presence and remembers it as their last chat room (see "Return to chat").
  """
  def enter_location(socket, location) do
    user = socket.assigns.current_user

    if connected?(socket) do
      topic = topic(socket.assigns.current_story.id)
      :ok = Stories.remember_location(user, location)

      Presence.update(self(), topic, to_string(user.id), fn meta ->
        Map.merge(meta, %{
          location_id: location.id,
          location_name: location.name,
          location_private: location.private
        })
      end)
    end

    assign(socket, :last_location, location)
  end

  @doc """
  The location a character is in, from the online list, when the viewer may
  follow them there: public locations for everyone, private ones only for
  the masters (who can always enter). `nil` when offline or not in a room.
  """
  def character_location(online, character_id, master? \\ false)

  def character_location(online, character_id, master?)
      when is_list(online) and not is_nil(character_id) do
    Enum.find_value(online, fn entry ->
      if (entry[:character_id] == character_id and entry[:location_id]) &&
           (master? or !entry[:location_private]),
         do: %{id: entry.location_id, name: entry.location_name}
    end)
  end

  def character_location(_, _, _), do: nil

  @doc """
  The users online in a GDR: one entry per user (their most recent page),
  sorted by username.
  """
  def list_online(story_id) do
    story_id
    |> topic()
    |> Presence.list()
    |> Enum.map(fn {_key, %{metas: metas}} -> Enum.max_by(metas, & &1.online_at) end)
    |> Enum.sort_by(&String.downcase(&1.username))
  end
end
