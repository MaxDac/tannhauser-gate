defmodule TannhauserGate.Guilds.Rank do
  @moduledoc """
  A rank of a guild, ordered by `position`. Members are paid `salary` every
  pay interval of the GDR (see `TannhauserGate.Bank.pay_due/1`); members of a
  `leader` rank manage the guild (requests, invitations, ranks and expulsions
  of the non-leader members).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "guild_ranks" do
    field :name, :string
    field :position, :integer, default: 0
    field :salary, :integer, default: 0
    field :leader, :boolean, default: false

    belongs_to :guild, TannhauserGate.Guilds.Guild

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(rank, attrs) do
    rank
    |> cast(attrs, [:name, :position, :salary, :leader])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :position, :salary])
    |> validate_length(:name, max: 60)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:salary,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000_000
    )
    |> unique_constraint(:name, name: :guild_ranks_guild_id_name_index)
    |> check_constraint(:salary, name: :guild_ranks_salary_non_negative)
  end
end
