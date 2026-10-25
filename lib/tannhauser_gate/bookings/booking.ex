defmodule TannhauserGate.Bookings.Booking do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A time slot booked in a private location by a player (through one of their
  playable characters), with the characters they invited.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Bookings.Invite
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Stories.Location

  @max_hours 12

  schema "location_bookings" do
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime

    belongs_to :location, Location
    belongs_to :user, User
    belongs_to :character, Character
    has_many :invites, Invite
    has_many :invited_characters, through: [:invites, :character]

    timestamps(type: :utc_datetime)
  end

  def max_hours, do: @max_hours

  @doc false
  def changeset(booking, attrs, now) do
    booking
    |> cast(attrs, [:starts_at, :ends_at])
    |> validate_required([:starts_at, :ends_at])
    |> validate_slot(now)
  end

  defp validate_slot(changeset, now) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    cond do
      is_nil(starts_at) or is_nil(ends_at) ->
        changeset

      DateTime.compare(ends_at, starts_at) != :gt ->
        add_error(changeset, :ends_at, dgettext_noop("errors", "must be after the start"))

      DateTime.compare(ends_at, now) != :gt ->
        add_error(changeset, :ends_at, dgettext_noop("errors", "must be in the future"))

      DateTime.diff(ends_at, starts_at) > @max_hours * 3600 ->
        add_error(
          changeset,
          :ends_at,
          dgettext_noop("errors", "a booking can last at most %{max_hours} hours"),
          max_hours: @max_hours
        )

      DateTime.diff(starts_at, now, :day) > 30 ->
        add_error(
          changeset,
          :starts_at,
          dgettext_noop("errors", "can be at most 30 days from now")
        )

      true ->
        changeset
    end
  end
end
