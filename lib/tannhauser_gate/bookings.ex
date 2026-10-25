defmodule TannhauserGate.Bookings do
  @moduledoc """
  Private locations. A GDR admin flags a location as private; a player with a
  playable character books it for a time slot (bookings never overlap) and
  invites other characters. During a booking only the booker, the owners of
  the invited characters and the masters can view the room and post in it;
  outside bookings only the masters can.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Bookings.{Booking, Invite}
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Guilds
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Location

  @pubsub TannhauserGate.PubSub

  def topic(location_id), do: "bookings:#{location_id}"

  def subscribe(location_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(location_id))

  @doc "Bookings of a location not ended yet, soonest first."
  def list_upcoming(%Location{id: location_id}, now \\ DateTime.utc_now()) do
    Repo.all(
      from b in Booking,
        where: b.location_id == ^location_id and b.ends_at > ^now,
        order_by: [asc: b.starts_at],
        preload: [:character, :user, :invited_characters]
    )
  end

  @doc "Map of `location_id => [booking]` with the bookings not ended yet of a story."
  def upcoming_by_location(story_id, now \\ DateTime.utc_now()) do
    Repo.all(
      from b in Booking,
        join: l in Location,
        on: l.id == b.location_id,
        where: l.story_id == ^story_id and b.ends_at > ^now,
        order_by: [asc: b.starts_at],
        preload: [:character]
    )
    |> Enum.group_by(& &1.location_id)
  end

  @doc "The booking running at `at` in a location, or nil."
  def active_booking(%Location{id: location_id}, at \\ DateTime.utc_now()) do
    Repo.one(
      from b in Booking,
        where: b.location_id == ^location_id and b.starts_at <= ^at and b.ends_at > ^at,
        limit: 1,
        preload: [:character, :user, :invited_characters]
    )
  end

  @doc "Gets a booking of a location, or nil."
  def get_booking(%Location{id: location_id}, id) do
    Repo.one(
      from b in Booking,
        where: b.id == ^id and b.location_id == ^location_id,
        preload: [:character, :user, :invited_characters]
    )
  end

  @doc """
  Whether a user can view and post in a location at `at`: always for non
  private locations and for the masters, otherwise only the booker and the
  owners (or, for NPCs, nobody but masters) of the invited characters of the
  running booking. A location restricted to a guild (guilds module) is
  further limited to the masters and the owners of the guild's active
  members.
  """
  def can_access?(user, location, at \\ DateTime.utc_now())

  def can_access?(user, %Location{} = location, at) do
    guild_access?(user, location) and booking_access?(user, location, at)
  end

  def can_access?(_user, _location, _at), do: false

  defp booking_access?(_user, %Location{private: false}, _at), do: true

  defp booking_access?(%User{} = user, %Location{} = location, at) do
    master?(user, location) or participant?(user, active_booking(location, at))
  end

  defp booking_access?(_user, _location, _at), do: false

  @doc """
  Whether the location is restricted to a guild the user is not part of:
  false for unrestricted locations, when the guilds module is off and for the
  masters.
  """
  def guild_locked?(user, %Location{} = location), do: not guild_access?(user, location)

  defp guild_access?(_user, %Location{guild_id: nil}), do: true

  defp guild_access?(user, %Location{guild_id: guild_id} = location) do
    story = story_of(location)

    not Guilds.enabled?(story) or Stories.master?(user, story) or
      Guilds.active_member_user?(user, guild_id)
  end

  @doc "Whether the user booked or was invited (with a character they own) to a booking."
  def participant?(%User{id: user_id}, %Booking{} = booking) do
    booking.user_id == user_id or
      Enum.any?(booking.invited_characters, &(&1.user_id == user_id and not &1.is_npc))
  end

  def participant?(_, _), do: false

  @doc """
  Books a private location. `attrs` carries `"character_id"` (one of the
  user's playable characters), `"starts_at"`, `"ends_at"` and
  `"invitee_ids"` (characters of the same GDR).
  """
  def create_booking(%User{} = user, %Location{} = location, attrs, now \\ DateTime.utc_now()) do
    with true <- location.private || {:error, :not_private},
         %Character{} = character <- fetch_character(attrs["character_id"]),
         true <- character.story_id == location.story_id || {:error, :unauthorized},
         true <- Characters.can_act_as?(user, character) || {:error, :cannot_play},
         {:ok, invitees} <- fetch_invitees(location, character, attrs["invitee_ids"]) do
      changeset =
        Booking.changeset(
          %Booking{location_id: location.id, user_id: user.id, character_id: character.id},
          attrs,
          now
        )

      Repo.transaction(fn -> insert_booking(location, changeset, invitees) end)
      |> case do
        {:ok, booking} ->
          broadcast(location.id)
          {:ok, Repo.preload(booking, [:character, :user, :invited_characters])}

        error ->
          error
      end
    else
      nil -> {:error, :character_not_found}
      {:error, _} = error -> error
    end
  end

  defp insert_booking(location, changeset, invitees) do
    # Lock the location so concurrent bookings are checked one at a time.
    Repo.one!(from l in Location, where: l.id == ^location.id, lock: "FOR UPDATE")

    with true <- changeset.valid? || changeset,
         true <- not overlaps?(changeset) || {:error, :overlap},
         {:ok, booking} <- Repo.insert(changeset) do
      Repo.insert_all(Invite, Enum.map(invitees, &%{booking_id: booking.id, character_id: &1.id}))
      booking
    else
      {:error, reason} -> Repo.rollback(reason)
      %Ecto.Changeset{} = changeset -> Repo.rollback(%{changeset | action: :insert})
    end
  end

  defp overlaps?(changeset) do
    location_id = Ecto.Changeset.get_field(changeset, :location_id)
    starts_at = Ecto.Changeset.get_field(changeset, :starts_at)
    ends_at = Ecto.Changeset.get_field(changeset, :ends_at)

    Repo.exists?(
      from b in Booking,
        where: b.location_id == ^location_id and b.starts_at < ^ends_at and b.ends_at > ^starts_at
    )
  end

  @doc "Cancels a booking: allowed to its booker and to the masters."
  def cancel_booking(%User{} = user, %Booking{} = booking) do
    location = Stories.get_location!(booking.location_id)

    if booking.user_id == user.id or master?(user, location) do
      with {:ok, booking} <- Repo.delete(booking) do
        broadcast(booking.location_id)
        {:ok, booking}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc "A form changeset for a booking."
  def change_booking(attrs \\ %{}),
    do: Booking.changeset(%Booking{}, attrs, DateTime.utc_now())

  @doc "A human readable message for the booking errors."
  def error_message(:not_private), do: "Only private locations can be booked."
  def error_message(:overlap), do: "That slot overlaps another booking."
  def error_message(:cannot_play), do: "That character cannot play yet."
  def error_message(:invalid_invitee), do: "You can only invite characters of this GDR."
  def error_message(:unauthorized), do: "You cannot manage that booking."
  def error_message(:character_not_found), do: "Choose one of your characters."

  def error_message(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _} -> message end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  def error_message(_), do: "The location could not be booked."

  defp master?(user, %Location{} = location), do: Stories.master?(user, story_of(location))

  defp story_of(%Location{story: %Stories.Story{} = story}), do: story
  defp story_of(%Location{story_id: story_id}), do: Stories.get_story(story_id)

  defp fetch_invitees(_location, _character, ids) when ids in [nil, "", []], do: {:ok, []}

  defp fetch_invitees(location, character, ids) do
    ids =
      ids
      |> List.wrap()
      |> Enum.flat_map(fn id ->
        case Integer.parse(to_string(id)) do
          {int, ""} -> [int]
          _ -> []
        end
      end)
      |> Enum.uniq()
      |> List.delete(character.id)

    invitees =
      Repo.all(from c in Character, where: c.id in ^ids and c.story_id == ^location.story_id)

    if length(invitees) == length(ids), do: {:ok, invitees}, else: {:error, :invalid_invitee}
  end

  defp fetch_character(id) when id in [nil, ""], do: nil

  defp fetch_character(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> Repo.get(Character, int)
      _ -> nil
    end
  end

  defp broadcast(location_id),
    do: Phoenix.PubSub.broadcast(@pubsub, topic(location_id), {:bookings_changed, location_id})
end
