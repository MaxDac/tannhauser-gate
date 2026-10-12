defmodule TannhauserGate.Bookings.Invite do
  @moduledoc "A character invited to a private location booking."
  use Ecto.Schema

  alias TannhauserGate.Bookings.Booking
  alias TannhauserGate.Characters.Character

  schema "booking_invites" do
    belongs_to :booking, Booking
    belongs_to :character, Character
  end
end
