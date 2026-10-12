defmodule TannhauserGate.Dice do
  @moduledoc """
  Server-side dice roller, configured per GDR by `TannhauserGate.Dice.Config`.

  `roll/3` rolls for a character: the request chooses sheet items (their
  values are summed into the pool or the modifier), a manual modifier, an
  optional difficulty and, for the expression system, the expression. The
  result is a plain map with string keys, ready to be stored as the `data` of
  a dice chat entry; `reroll/4` spends the configured tracker to reroll some
  failed dice of a pool result once.

  Randomness always comes from the server; tests can pass a deterministic
  `rng: fn sides -> value end` option.
  """

  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Dice.Config
  alias TannhauserGate.Sheet
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story
  alias TannhauserGate.Trackers

  @max_dice 50
  @max_terms 10
  @max_sides 1000
  @max_value 1000

  @type request :: %{
          optional(:items) => [String.t()],
          optional(:modifier) => integer(),
          optional(:difficulty) => integer() | nil,
          optional(:expression) => String.t() | nil,
          optional(:label) => String.t() | nil
        }

  @doc "The dice configuration of a story (defaults when never configured)."
  def config(%Story{dice_config: %Config{} = config}), do: config
  def config(%Story{}), do: %Config{}

  @doc """
  Rolls for a character with its GDR dice system.

  Options: `:story` (avoids reloading it), `:config` (overrides the story
  configuration), `:rng` (a `fn sides -> 1..sides end`).
  """
  @spec roll(struct(), map(), keyword()) :: {:ok, map()} | {:error, atom() | String.t()}
  def roll(%Character{} = character, request, opts \\ []) do
    story = opts[:story] || Stories.get_story!(character.story_id)
    config = opts[:config] || config(story)
    rng = opts[:rng] || (&:rand.uniform/1)
    request = normalize_request(request)

    with {:ok, items} <- item_values(character, story, request.items),
         {:ok, result} <- do_roll(config.system, config, request, items, rng, character) do
      {:ok, Map.put(result, "summary", summary(result))}
    end
  end

  @doc """
  Rerolls up to `reroll_max_dice` failed regular dice of a pool result once,
  spending the configured tracker of the character. `indexes` selects the dice
  (positions in `result["dice"]`); `nil` picks the first failed ones.
  """
  @spec reroll(struct(), map(), [integer()] | nil, keyword()) ::
          {:ok, map()} | {:error, atom()}
  def reroll(%Character{} = character, result, indexes \\ nil, opts \\ []) do
    story = opts[:story] || Stories.get_story!(character.story_id)
    config = opts[:config] || config(story)
    rng = opts[:rng] || (&:rand.uniform/1)

    with :ok <- check_rerollable(config, result),
         {:ok, indexes} <- reroll_indexes(config, result, indexes),
         {:ok, tracker} <- spend_reroll(character, config) do
      dice = reroll_dice(result["dice"], indexes, rng, config.die_size)

      evaluated =
        result
        |> Map.merge(evaluate_pool(config, dice, result["difficulty"]))
        |> Map.merge(%{
          "rerolled" => true,
          "rerolled_indexes" => indexes,
          "reroll_tracker" => tracker
        })

      {:ok, Map.put(evaluated, "summary", summary(evaluated))}
    end
  end

  defp reroll_dice(dice, indexes, rng, sides) do
    dice
    |> Enum.with_index()
    |> Enum.map(fn {die, index} -> reroll_die(die, index in indexes, rng, sides) end)
  end

  defp reroll_die(die, true, rng, sides), do: %{die | "value" => rng.(sides)}
  defp reroll_die(die, false, _rng, _sides), do: die

  @doc "Whether a stored dice result can still be rerolled with this configuration."
  def rerollable?(%Config{} = config, result), do: check_rerollable(config, result) == :ok

  @doc "A human readable message for the dice errors."
  def error_message(:unknown_item), do: "That sheet item does not exist."
  def error_message(:no_reroll), do: "This GDR has no rerolls."
  def error_message(:not_a_pool), do: "Only pool rolls can be rerolled."
  def error_message(:already_rerolled), do: "This roll was already rerolled."
  def error_message(:nothing_to_reroll), do: "There are no failed dice to reroll."
  def error_message(:invalid_dice), do: "Those dice cannot be rerolled."
  def error_message(:not_enough), do: "You do not have enough left to reroll."
  def error_message(:unauthorized), do: "You cannot reroll this roll."
  def error_message(message) when is_binary(message), do: message
  def error_message(reason), do: Trackers.error_message(reason)

  @doc "Human readable label of an outcome."
  def outcome_label("critical"), do: "Critical"
  def outcome_label("messy_critical"), do: "Messy critical"
  def outcome_label("success"), do: "Success"
  def outcome_label("failure"), do: "Failure"
  def outcome_label("bestial_failure"), do: "Bestial failure"
  def outcome_label("critical_failure"), do: "Critical failure"
  def outcome_label(_), do: nil

  ## Expressions

  @doc """
  Parses a dice expression such as `2d6+1d4-1` into terms:
  `{:dice, sign, count, sides}` and `{:constant, value}`.
  """
  @spec parse_expression(String.t() | nil) :: {:ok, list()} | {:error, String.t()}
  def parse_expression(expression) when is_binary(expression) do
    compact = expression |> String.downcase() |> String.replace(~r/\s+/, "")

    terms = Regex.scan(~r/([+-]?)(\d*d\d+|\d+)/, compact)
    rebuilt = Enum.map_join(terms, fn [whole | _] -> whole end)

    cond do
      compact == "" -> {:error, "is empty"}
      rebuilt != compact -> {:error, "must look like 2d6+1"}
      length(terms) > @max_terms -> {:error, "has too many terms"}
      true -> terms |> Enum.map(&parse_term/1) |> collect_terms()
    end
  end

  def parse_expression(_), do: {:error, "is empty"}

  defp parse_term([_whole, sign, term]) do
    sign = if sign == "-", do: -1, else: 1

    case String.split(term, "d") do
      ["", sides] -> dice_term(sign, 1, String.to_integer(sides))
      [count, sides] -> dice_term(sign, String.to_integer(count), String.to_integer(sides))
      [value] -> constant_term(sign, String.to_integer(value))
    end
  end

  defp dice_term(_sign, count, _sides) when count < 1 or count > @max_dice,
    do: {:error, "can roll 1 to #{@max_dice} dice"}

  defp dice_term(_sign, _count, sides) when sides < 2 or sides > @max_sides,
    do: {:error, "dice need 2 to #{@max_sides} sides"}

  defp dice_term(sign, count, sides), do: {:ok, {:dice, sign, count, sides}}

  defp constant_term(_sign, value) when value > @max_value,
    do: {:error, "numbers cannot exceed #{@max_value}"}

  defp constant_term(sign, value), do: {:ok, {:constant, sign * value}}

  defp collect_terms(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        terms = Enum.map(results, fn {:ok, term} -> term end)

        if Enum.any?(terms, &match?({:dice, _, _, _}, &1)),
          do: {:ok, terms},
          else: {:error, "must roll at least one die"}

      error ->
        error
    end
  end

  ## Rolling

  defp do_roll("expression", config, request, items, rng, _character) do
    expression = blank_to_nil(request.expression) || config.default_expression || "1d6"

    with {:ok, terms} <- parse_expression(expression) do
      groups =
        for {:dice, sign, count, sides} <- terms do
          %{"sign" => sign, "sides" => sides, "rolls" => roll_n(rng, count, sides)}
        end

      constant = for({:constant, value} <- terms, do: value) |> Enum.sum()
      rolled = Enum.sum(Enum.map(groups, &(&1["sign"] * Enum.sum(&1["rolls"]))))
      bonus = items_total(items) + request.modifier + constant
      total = rolled + bonus

      {:ok,
       base(config, request, items)
       |> Map.merge(%{
         "expression" => expression,
         "groups" => groups,
         "constant" => constant,
         "total" => total,
         "outcome" => target_outcome(total, request.difficulty)
       })}
    end
  end

  defp do_roll("d20", config, request, items, rng, _character) do
    natural = rng.(20)
    total = natural + items_total(items) + request.modifier

    outcome =
      cond do
        config.natural_crits and natural == 20 -> "critical"
        config.natural_crits and natural == 1 -> "critical_failure"
        true -> target_outcome(total, request.difficulty)
      end

    {:ok,
     base(config, request, items)
     |> Map.merge(%{
       "dice" => [%{"value" => natural}],
       "natural" => natural,
       "total" => total,
       "outcome" => outcome
     })}
  end

  defp do_roll("pool", config, request, items, rng, character) do
    pool = (items_total(items) + request.modifier) |> max(1) |> min(@max_dice)
    special = special_count(character, config, pool)
    difficulty = request.difficulty || config.default_difficulty

    dice =
      for index <- 1..pool//1 do
        %{"value" => rng.(config.die_size), "special" => index > pool - special}
      end

    {:ok,
     base(config, request, items)
     |> Map.merge(%{
       "pool" => pool,
       "special_count" => special,
       "difficulty" => difficulty,
       "rerolled" => false
     })
     |> Map.merge(evaluate_pool(config, dice, difficulty))}
  end

  defp do_roll(_system, _config, _request, _items, _rng, _character),
    do: {:error, "Unknown dice system."}

  defp evaluate_pool(config, dice, difficulty) do
    max = config.die_size
    dice = Enum.map(dice, &Map.put(&1, "success", &1["value"] >= config.success_threshold))
    maxes = Enum.filter(dice, &(&1["value"] == max))
    pairs = if config.crit_rule == "pairs", do: div(length(maxes), 2), else: 0
    successes = Enum.count(dice, & &1["success"]) + pairs * config.crit_bonus

    outcome =
      if succeeded?(successes, difficulty),
        do: success_outcome(config, pairs, maxes),
        else: failure_outcome(config, dice)

    %{
      "dice" => dice,
      "crits" => pairs,
      "successes" => successes,
      "margin" => margin(successes, difficulty),
      "outcome" => outcome
    }
  end

  defp succeeded?(successes, nil), do: successes > 0
  defp succeeded?(successes, difficulty), do: successes >= difficulty

  defp margin(_successes, nil), do: nil
  defp margin(successes, difficulty), do: successes - difficulty

  defp success_outcome(_config, 0, _maxes), do: "success"

  defp success_outcome(config, _pairs, maxes) do
    if config.messy_crit and Enum.any?(maxes, & &1["special"]),
      do: "messy_critical",
      else: "critical"
  end

  defp failure_outcome(config, dice) do
    if config.bestial_failure and Enum.any?(dice, &(&1["special"] and &1["value"] == 1)),
      do: "bestial_failure",
      else: "failure"
  end

  defp special_count(_character, %Config{special_tracker: slug}, _pool) when slug in [nil, ""],
    do: 0

  defp special_count(character, %Config{special_tracker: slug}, pool) do
    case Trackers.get(character, slug) do
      %{value: value} when is_integer(value) -> value |> max(0) |> min(pool)
      _ -> 0
    end
  end

  defp base(config, request, items) do
    %{
      "system" => config.system,
      "label" => blank_to_nil(request.label),
      "items" => items,
      "modifier" => request.modifier,
      "difficulty" => request.difficulty
    }
  end

  defp target_outcome(_total, nil), do: nil
  defp target_outcome(total, difficulty) when total >= difficulty, do: "success"
  defp target_outcome(_total, _difficulty), do: "failure"

  defp roll_n(rng, count, sides), do: for(_ <- 1..count//1, do: rng.(sides))

  defp items_total(items), do: items |> Enum.map(& &1["value"]) |> Enum.sum()

  defp item_values(_character, _story, []), do: {:ok, []}

  defp item_values(character, story, slugs) do
    names = Map.new(Sheet.list_items(story), &{&1.slug, &1.name})
    values = Characters.values_by_slug(character)

    if Enum.all?(slugs, &Map.has_key?(names, &1)) do
      {:ok,
       Enum.map(slugs, fn slug ->
         %{"slug" => slug, "name" => names[slug], "value" => Map.get(values, slug, 0)}
       end)}
    else
      {:error, :unknown_item}
    end
  end

  ## Reroll

  defp check_rerollable(%Config{reroll_tracker: slug}, _result) when slug in [nil, ""],
    do: {:error, :no_reroll}

  defp check_rerollable(%Config{reroll_max_dice: 0}, _result), do: {:error, :no_reroll}

  defp check_rerollable(_config, %{"system" => system}) when system != "pool",
    do: {:error, :not_a_pool}

  defp check_rerollable(_config, %{"rerolled" => true}), do: {:error, :already_rerolled}

  defp check_rerollable(_config, %{"dice" => dice}) do
    if Enum.any?(dice, &failed_regular?/1), do: :ok, else: {:error, :nothing_to_reroll}
  end

  defp check_rerollable(_config, _result), do: {:error, :not_a_pool}

  defp failed_regular?(die), do: !die["special"] and !die["success"]

  defp reroll_indexes(config, result, nil) do
    indexes =
      result["dice"]
      |> Enum.with_index()
      |> Enum.filter(fn {die, _} -> failed_regular?(die) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.take(config.reroll_max_dice)

    {:ok, indexes}
  end

  defp reroll_indexes(config, result, indexes) do
    indexes = Enum.uniq(indexes)
    dice = result["dice"]

    valid? =
      indexes != [] and length(indexes) <= config.reroll_max_dice and
        Enum.all?(indexes, fn i ->
          is_integer(i) and i >= 0 and i < length(dice) and failed_regular?(Enum.at(dice, i))
        end)

    if valid?, do: {:ok, Enum.sort(indexes)}, else: {:error, :invalid_dice}
  end

  defp spend_reroll(character, %Config{reroll_tracker: slug} = config) do
    cost = config.reroll_cost
    type = blank_to_nil(config.reroll_damage_type)

    case Trackers.get(character, slug) do
      nil ->
        {:error, :not_found}

      %{error: error} when is_binary(error) ->
        {:error, :not_enough}

      state ->
        {available, delta} =
          if type, do: {state.remaining, {type, cost}}, else: {state.value, -cost}

        with true <- available >= cost || {:error, :not_enough},
             {:ok, _} <- Trackers.adjust(character, slug, delta) do
          {:ok, state.tracker.name}
        end
    end
  end

  ## Summary

  @doc "One line summary of a result, e.g. `Pool 5: 3 successes - Success`."
  def summary(%{"system" => "pool"} = result) do
    successes = result["successes"]
    noun = if successes == 1, do: "success", else: "successes"
    against = if result["difficulty"], do: " vs #{result["difficulty"]}", else: ""

    "Pool #{result["pool"]}: #{successes} #{noun}#{against} - #{outcome_label(result["outcome"])}"
  end

  def summary(%{"system" => "d20"} = result) do
    against = if result["difficulty"], do: " vs #{result["difficulty"]}", else: ""
    outcome = outcome_label(result["outcome"])

    "d20 (#{result["natural"]}) = #{result["total"]}#{against}" <>
      if(outcome, do: " - #{outcome}", else: "")
  end

  def summary(%{"system" => "expression"} = result) do
    against = if result["difficulty"], do: " vs #{result["difficulty"]}", else: ""
    outcome = outcome_label(result["outcome"])

    "#{result["expression"]} = #{result["total"]}#{against}" <>
      if(outcome, do: " - #{outcome}", else: "")
  end

  def summary(_), do: ""

  ## Request

  defp normalize_request(request) do
    get = fn key -> Map.get(request, key, Map.get(request, Atom.to_string(key))) end

    %{
      items: get.(:items) |> List.wrap() |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq(),
      modifier: to_int(get.(:modifier)) || 0,
      difficulty: to_int(get.(:difficulty)),
      expression: get.(:expression),
      label: get.(:label) |> then(&if(is_binary(&1), do: String.slice(&1, 0, 80)))
    }
  end

  defp to_int(value) when is_integer(value), do: value |> max(-@max_value) |> min(@max_value)

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> to_int(int)
      _ -> nil
    end
  end

  defp to_int(_), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil
end
