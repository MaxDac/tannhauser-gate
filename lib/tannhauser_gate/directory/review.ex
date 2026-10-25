defmodule TannhauserGate.Directory.Review do
  @moduledoc """
  A player's review of a GDR in the portal directory: a 1–5 score per rubric
  criterion (see `criteria/0`), free-text advice and a required conclusion.
  The GDR admin can reply once (editable) and platform admins can hide it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Stories.Story

  @criteria [:graphics, :setting, :play_level, :technical, :features, :documentation, :management]

  schema "gdr_reviews" do
    field :graphics, :integer
    field :setting, :integer
    field :play_level, :integer
    field :technical, :integer
    field :features, :integer
    field :documentation, :integer
    field :management, :integer
    field :advice, :string
    field :conclusion, :string
    field :gm_reply, :string
    field :replied_at, :utc_datetime
    field :hidden_at, :utc_datetime

    belongs_to :story, Story
    belongs_to :user, User
    belongs_to :hidden_by, User

    timestamps(type: :utc_datetime)
  end

  @doc "The score fields, in rubric order."
  def criteria, do: @criteria

  @doc "Changeset for the author writing or editing the review."
  def changeset(review, attrs) do
    review
    |> cast(attrs, @criteria ++ [:advice, :conclusion])
    |> validate_required(@criteria ++ [:conclusion])
    |> then(fn changeset ->
      Enum.reduce(@criteria, changeset, fn field, acc ->
        validate_number(acc, field, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
      end)
    end)
    |> validate_length(:advice, max: 5000)
    |> validate_length(:conclusion, min: 10, max: 5000)
    |> unique_constraint([:story_id, :user_id], message: "you already reviewed this GDR")
  end

  @doc "Changeset for the GDR admin's reply."
  def reply_changeset(review, attrs) do
    review
    |> cast(attrs, [:gm_reply])
    |> validate_required([:gm_reply])
    |> validate_length(:gm_reply, max: 5000)
    |> put_change(:replied_at, DateTime.utc_now(:second))
  end

  @doc "The overall score: the mean of the criteria."
  def overall(%__MODULE__{} = review) do
    scores = Enum.map(@criteria, &Map.get(review, &1))

    if Enum.all?(scores, &is_integer/1), do: Enum.sum(scores) / length(scores), else: nil
  end
end
