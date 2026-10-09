defmodule TannhauserGate.GdrRequests.GdrRequest do
  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  schema "gdr_requests" do
    field :name, :string
    field :pitch, :string
    field :status, :string, default: "pending"

    belongs_to :user, User
    belongs_to :reviewed_by, User
    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:name, :pitch])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_length(:pitch, max: 5000)
  end
end
