defmodule TannhauserGate.Sheet.Item do
  @moduledoc """
  An attribute, skill or power defined by a game master for their GDR.
  Characters hold a numeric value between `min_value` and `max_value` for each.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Story

  @kinds ~w(attribute skill power)

  schema "sheet_items" do
    field :kind, :string
    field :name, :string
    field :description, :string
    field :min_value, :integer, default: 0
    field :max_value, :integer, default: 10
    field :position, :integer, default: 0

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:kind, :name, :description, :min_value, :max_value, :position])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:kind, :name, :min_value, :max_value])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_number(:min_value, greater_than_or_equal_to: -1_000, less_than_or_equal_to: 1_000)
    |> validate_number(:max_value, greater_than_or_equal_to: -1_000, less_than_or_equal_to: 1_000)
    |> validate_min_max()
    |> unique_constraint([:story_id, :kind, :name],
      name: :sheet_items_story_id_kind_name_index,
      message: "already exists"
    )
  end

  defp validate_min_max(changeset) do
    min = get_field(changeset, :min_value)
    max = get_field(changeset, :max_value)

    if is_integer(min) and is_integer(max) and max < min do
      add_error(changeset, :max_value, "must be greater than or equal to the minimum")
    else
      changeset
    end
  end
end
