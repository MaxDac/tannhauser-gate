defmodule TannhauserGate.Dice.Config do
  @moduledoc """
  The dice system of a GDR, chosen by its GDR admin (embedded in the story).

    * `"expression"` - a generic `NdX+M` expression (e.g. `2d6+1`), plus the
      chosen sheet items and modifier;
    * `"d20"` - one d20 plus the chosen items and modifier, against an
      optional difficulty (natural 20/1 are criticals when `natural_crits`);
    * `"pool"` - a success pool: roll as many `die_size` dice as the chosen
      items plus the modifier; each die reaching `success_threshold` is a
      success. With the `"pairs"` crit rule every pair of maximum results adds
      `crit_bonus` successes. A tracker (e.g. hunger) can turn some dice into
      special dice, enabling messy criticals (a critical including a special
      maximum) and bestial failures (a failure with a special 1). Another
      tracker (e.g. willpower) can be spent to reroll up to
      `reroll_max_dice` failed regular dice once.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @systems ~w(expression d20 pool)
  @crit_rules ~w(none pairs)

  @primary_key false
  embedded_schema do
    field :system, :string, default: "expression"

    # expression
    field :default_expression, :string, default: "2d6"

    # d20
    field :natural_crits, :boolean, default: true

    # pool
    field :die_size, :integer, default: 10
    field :success_threshold, :integer, default: 6
    field :default_difficulty, :integer
    field :crit_rule, :string, default: "pairs"
    field :crit_bonus, :integer, default: 2
    field :special_tracker, :string
    field :messy_crit, :boolean, default: false
    field :bestial_failure, :boolean, default: false
    field :reroll_tracker, :string
    field :reroll_damage_type, :string
    field :reroll_cost, :integer, default: 1
    field :reroll_max_dice, :integer, default: 3
  end

  def systems, do: @systems
  def crit_rules, do: @crit_rules

  @fields [
    :system,
    :default_expression,
    :natural_crits,
    :die_size,
    :success_threshold,
    :default_difficulty,
    :crit_rule,
    :crit_bonus,
    :special_tracker,
    :messy_crit,
    :bestial_failure,
    :reroll_tracker,
    :reroll_damage_type,
    :reroll_cost,
    :reroll_max_dice
  ]

  @doc false
  def changeset(config, attrs) do
    config
    |> cast(attrs, @fields, empty_values: [""])
    |> validate_required([:system, :die_size, :success_threshold, :crit_rule])
    |> validate_inclusion(:system, @systems)
    |> validate_inclusion(:crit_rule, @crit_rules)
    |> validate_number(:die_size, greater_than_or_equal_to: 2, less_than_or_equal_to: 100)
    |> validate_number(:success_threshold, greater_than_or_equal_to: 1)
    |> validate_threshold()
    |> validate_number(:default_difficulty, greater_than_or_equal_to: 0)
    |> validate_number(:crit_bonus, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:reroll_cost, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:reroll_max_dice, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_length(:reroll_damage_type, max: 40)
    |> validate_expression()
  end

  defp validate_threshold(changeset) do
    die_size = get_field(changeset, :die_size)
    threshold = get_field(changeset, :success_threshold)

    if is_integer(die_size) and is_integer(threshold) and threshold > die_size,
      do: add_error(changeset, :success_threshold, "cannot be higher than the die size"),
      else: changeset
  end

  defp validate_expression(changeset) do
    validate_change(changeset, :default_expression, fn :default_expression, value ->
      case TannhauserGate.Dice.parse_expression(value) do
        {:ok, _} -> []
        {:error, message} -> [default_expression: message]
      end
    end)
  end
end
