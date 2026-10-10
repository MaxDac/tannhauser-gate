defmodule TannhauserGate.Bank.Job do
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Stories.Story

  schema "jobs" do
    field :name, :string
    field :description, :string
    field :pay, :integer, default: 0

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:name, :description, :pay])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :pay])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 2_000)
    |> validate_number(:pay, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000_000)
    |> unique_constraint([:story_id, :name],
      name: :jobs_story_id_name_index,
      message: "already exists"
    )
  end
end
