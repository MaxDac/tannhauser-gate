defmodule TannhauserGateWeb.GdrPresence do
  @moduledoc """
  Tracks the users online in a GDR, with the character they play and the
  location they are in, and keeps the `:online` assign (shown in the
  layout) up to date.

  Mounted with `on_mount {TannhauserGateWeb.GdrPresence, :track}` after
  `UserAuth`'s `:load_story`; rooms call `enter_location/2`.

  Each user also shows a presence status (available, busy, away, looking for
  play), saved per GDR (`Stories.set_presence_status/3`) and changed from the
  drawer with the `"set_presence_status"` event, handled here for every
  LiveView of the GDR.
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
          status: Stories.presence_status(user, story.id),
          online_at: System.system_time(:millisecond)
        })

      Phoenix.PubSub.subscribe(TannhauserGate.PubSub, topic)

      {:cont,
       socket
       |> assign(:online, list_online(story.id))
       |> attach_hook(:gdr_presence, :handle_info, &handle_info/2)
       |> attach_hook(:gdr_presence_status, :handle_event, &handle_event/3)}
    else
      {:cont, assign(socket, :online, [])}
    end
  end

  defp handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:halt, assign(socket, :online, list_online(socket.assigns.current_story.id))}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("set_presence_status", %{"presence" => %{"status" => status}}, socket) do
    %{current_user: user, current_story: story} = socket.assigns

    case Stories.set_presence_status(user, story.id, status) do
      {:ok, status} ->
        # Bumping `online_at` makes this page the one listed for the user.
        Presence.update(self(), topic(story.id), to_string(user.id), fn meta ->
          Map.merge(meta, %{status: status, online_at: System.system_time(:millisecond)})
        end)

        {:halt, assign(socket, :online, list_online(story.id))}

      {:error, _} ->
        {:halt, socket}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

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

  @doc "The presence status of the player of an online character, or nil."
  def character_status(online, character_id) when is_list(online) and not is_nil(character_id) do
    Enum.find_value(online, &(&1[:character_id] == character_id && (&1[:status] || "available")))
  end

  def character_status(_, _), do: nil

  @doc "The presence status of a user, from the online list (nil when offline)."
  def user_status(online, user_id) when is_list(online) do
    Enum.find_value(online, &(&1[:user_id] == user_id && (&1[:status] || "available")))
  end

  def user_status(_, _), do: nil

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
