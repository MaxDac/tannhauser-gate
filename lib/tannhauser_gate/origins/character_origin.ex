defmodule TannhauserGate.Origins.CharacterOrigin do
  @moduledoc "The option a character picked in an origin group (one per group)."
  use Ecto.Schema

  alias TannhauserGate.Origins.{Group, Option}

  schema "character_origins" do
    belongs_to :character, TannhauserGate.Characters.Character
    belongs_to :origin_group, Group
    belongs_to :origin_option, Option

    timestamps(type: :utc_datetime)
  end
end
