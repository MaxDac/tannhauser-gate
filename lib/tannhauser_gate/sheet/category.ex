defmodule TannhauserGate.Sheet.Category do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  Per-GDR configuration of a sheet category (attributes, skills or powers):
  the character creation budget and the XP cost formula used to raise items.

  Creation modes:

    * `"free"` - no budget, any value within each item's range
    * `"points"` - a pool of points to spend above the starting value
    * `"distribution"` - an ordered list of values (e.g. `"4,3,3,2,2,2,1"`)
      that must be assigned to the category items; the remaining items keep
      the starting value
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TannhauserGate.Formula
  alias TannhauserGate.Sheet.Item
  alias TannhauserGate.Stories.Story

  @modes ~w(free points distribution)
  @xp_variables ~w(current next)

  schema "sheet_categories" do
    field :kind, :string
    field :creation_mode, :string, default: "free"
    field :creation_points, :integer
    field :creation_distribution, :string
    field :starting_value, :integer, default: 0
    field :xp_cost_formula, :string

    belongs_to :story, Story

    timestamps(type: :utc_datetime)
  end

  def modes, do: @modes
  def xp_variables, do: @xp_variables

  @doc """
  `slugs` are the sheet item keys the XP cost formula may reference besides
  `current` and `next`.
  """
  def changeset(category, attrs, slugs \\ []) do
    category
    |> cast(attrs, [
      :creation_mode,
      :creation_points,
      :creation_distribution,
      :starting_value,
      :xp_cost_formula
    ])
    |> update_change(:xp_cost_formula, &(&1 && String.trim(&1)))
    |> validate_required([:kind, :creation_mode, :starting_value])
    |> validate_inclusion(:kind, Item.kinds())
    |> validate_inclusion(:creation_mode, @modes)
    |> validate_number(:starting_value,
      greater_than_or_equal_to: -1_000,
      less_than_or_equal_to: 1_000
    )
    |> validate_mode()
    |> validate_length(:xp_cost_formula, max: 200)
    |> Formula.validate_formula(:xp_cost_formula, @xp_variables ++ slugs)
    |> unique_constraint([:story_id, :kind])
  end

  defp validate_mode(changeset) do
    case get_field(changeset, :creation_mode) do
      "points" ->
        changeset
        |> validate_required([:creation_points],
          message: dgettext_noop("errors", "is required for a points pool")
        )
        |> validate_number(:creation_points,
          greater_than_or_equal_to: 0,
          less_than_or_equal_to: 1_000
        )

      "distribution" ->
        changeset
        |> validate_required([:creation_distribution],
          message: dgettext_noop("errors", "is required for a distribution")
        )
        |> normalize_distribution()

      _ ->
        changeset
    end
  end

  defp normalize_distribution(changeset) do
    case get_field(changeset, :creation_distribution) do
      nil ->
        changeset

      raw ->
        case parse_distribution(raw) do
          {:ok, values} ->
            put_change(changeset, :creation_distribution, Enum.join(values, ","))

          :error ->
            add_error(
              changeset,
              :creation_distribution,
              dgettext_noop("errors", "must be a list of numbers like 4,3,3,2")
            )
        end
    end
  end

  @doc "Parses a distribution string into a list of integers (sorted descending)."
  def parse_distribution(raw) when is_binary(raw) do
    parts = raw |> String.split([",", " ", ";"], trim: true)

    values =
      Enum.map(parts, fn part ->
        case Integer.parse(part) do
          {n, ""} when n >= -1_000 and n <= 1_000 -> n
          _ -> :error
        end
      end)

    if values == [] or Enum.member?(values, :error) or length(values) > 100,
      do: :error,
      else: {:ok, Enum.sort(values, :desc)}
  end

  def parse_distribution(_), do: :error

  @doc "The distribution values of a category (empty when not configured)."
  def distribution(%__MODULE__{creation_distribution: raw}) do
    case parse_distribution(raw) do
      {:ok, values} -> values
      :error -> []
    end
  end

  def budgeted?(%__MODULE__{creation_mode: mode}), do: mode in ~w(points distribution)
end
