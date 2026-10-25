defmodule TannhauserGate.Characters.State do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A character state defined by the GDR admin (e.g. "Active", "Dead",
  "Torpor"). Characters in a state without `can_play` cannot play.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Story

  schema "character_states" do
    field :name, :string
    field :can_play, :boolean, default: true
    field :position, :integer, default: 0

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:name, :can_play, :position])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
    |> unique_constraint(:name,
      name: :character_states_story_id_name_index,
      message: dgettext_noop("errors", "already exists in this GDR")
    )
  end
end
