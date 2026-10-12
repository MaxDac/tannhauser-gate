defmodule TannhauserGate.Experience do
  @moduledoc """
  Experience points (XP). Masters (and the GDR admin) award XP to characters,
  with a reason; a negative award is a correction. The owner of a playable
  character spends XP to raise its sheet items, at the cost given by the
  formula the GDR admin configured for the item category (variables
  `current`, `next` and the sheet item keys, see `TannhauserGate.Formula`).

  Every award and spend is recorded in the character's XP log.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Experience.Entry
  alias TannhauserGate.Formula
  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet
  alias TannhauserGate.Sheet.{Item, Trait}
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  @max_award 1_000

  ## Awards

  @doc """
  Awards `amount` XP (negative for a correction) to a character, with a
  required reason. Only the masters of its GDR can do it.

  Errors: `:unauthorized`, `:invalid_amount`, `:reason_required`,
  `:insufficient_xp` (a correction cannot leave the available XP negative).
  """
  def award(%User{} = master, %Character{} = character, amount, reason) do
    reason = if is_binary(reason), do: String.trim(reason), else: ""

    with :ok <- authorize_master(master, character),
         {:ok, amount} <- parse_amount(amount),
         :ok <- if(reason == "", do: {:error, :reason_required}, else: :ok) do
      Repo.transaction(fn -> do_award(master, character, amount, reason) end)
    end
  end

  defp do_award(master, character, amount, reason) do
    lock_character!(character)

    if amount < 0 and totals(character).available + amount < 0 do
      Repo.rollback(:insufficient_xp)
    end

    insert_entry!(character, %{
      kind: "award",
      amount: amount,
      reason: String.slice(reason, 0, 500),
      author_id: master.id
    })
  end

  defp authorize_master(user, character) do
    if Stories.master?(user, story_of(character)), do: :ok, else: {:error, :unauthorized}
  end

  defp parse_amount(amount) when is_integer(amount) and amount != 0 and abs(amount) <= @max_award,
    do: {:ok, amount}

  defp parse_amount(amount) when is_binary(amount) do
    case Integer.parse(String.trim(amount)) do
      {n, ""} -> parse_amount(n)
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_amount(_), do: {:error, :invalid_amount}

  ## Spending

  @doc """
  Spends XP to raise a sheet item of the character by one point. Only the
  owner of a playable player character can do it.

  Errors: `:unauthorized`, `:cannot_play`, `:not_found`, `:not_purchasable`
  (no cost configured for the category), `:at_max`, `:insufficient_xp`,
  `:invalid_formula`.
  """
  def spend(%User{id: user_id}, %Character{} = character, item_id) do
    cond do
      character.is_npc or character.user_id != user_id ->
        {:error, :unauthorized}

      not Characters.can_play?(character) ->
        {:error, :cannot_play}

      true ->
        Repo.transaction(fn -> do_spend(user_id, character, item_id) end)
    end
  end

  defp do_spend(user_id, character, item_id) do
    lock_character!(character)

    with %Item{} = item <- get_item(character, item_id),
         {:ok, offer} <- price_raise(character, item),
         :ok <- check_available(character, offer.cost) do
      upsert_trait!(character, item, offer.next)

      insert_entry!(character, %{
        kind: "spend",
        amount: offer.cost,
        author_id: user_id,
        sheet_item_id: item.id,
        item_name: item.name,
        from_value: offer.current,
        to_value: offer.next
      })
    else
      nil -> Repo.rollback(:not_found)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  The XP cost to raise an item of the character by one point:
  `{:ok, cost}` or `{:error, :not_purchasable | :at_max | :invalid_formula}`.
  """
  def cost(%Character{} = character, %Item{} = item) do
    with {:ok, offer} <- price_raise(character, item), do: {:ok, offer.cost}
  end

  @doc """
  The raise costs of every item of the character's GDR, as a map
  `item_id => {:ok, cost} | {:error, reason}` (computed in one pass).
  """
  def costs(%Character{} = character) do
    story = %Story{id: character.story_id}
    categories = Sheet.categories(story)
    sheet = Characters.sheet(character)
    values = slug_values(sheet)

    for {kind, entries} <- sheet, {item, value} <- entries, into: %{} do
      {item.id, compute_cost(Map.fetch!(categories, kind), item, value, values)}
    end
  end

  defp price_raise(character, item) do
    category = Sheet.get_category(%Story{id: character.story_id}, item.kind)
    sheet = Characters.sheet(character)
    values = slug_values(sheet)
    current = Map.get(values, item.slug, item.min_value)

    with {:ok, cost} <- compute_cost(category, item, current, values) do
      {:ok, %{cost: cost, current: current, next: current + 1}}
    end
  end

  defp compute_cost(category, item, current, values) do
    cond do
      category.xp_cost_formula in [nil, ""] ->
        {:error, :not_purchasable}

      current >= item.max_value ->
        {:error, :at_max}

      true ->
        vars = Map.merge(values, %{"current" => current, "next" => current + 1})

        case Formula.evaluate(category.xp_cost_formula, vars) do
          {:ok, cost} -> {:ok, max(cost, 0)}
          {:error, _} -> {:error, :invalid_formula}
        end
    end
  end

  defp slug_values(sheet) do
    for {_kind, entries} <- sheet, {item, value} <- entries, into: %{}, do: {item.slug, value}
  end

  defp check_available(character, cost) do
    if totals(character).available >= cost, do: :ok, else: {:error, :insufficient_xp}
  end

  defp get_item(character, item_id) do
    case Integer.parse(to_string(item_id)) do
      {id, ""} -> Repo.get_by(Item, id: id, story_id: character.story_id)
      _ -> nil
    end
  end

  defp upsert_trait!(character, item, value) do
    Repo.insert_all(
      Trait,
      [%{character_id: character.id, sheet_item_id: item.id, value: value}],
      on_conflict: {:replace, [:value]},
      conflict_target: [:character_id, :sheet_item_id]
    )
  end

  ## Totals and log

  @doc "XP totals of a character: `%{earned: n, spent: n, available: n}`."
  def totals(%Character{id: id}) do
    Map.get(totals_query([id]), id, empty_totals())
  end

  @doc "XP totals of every character of a story, as `character_id => totals`."
  def totals_by_character(story_id) do
    ids = Repo.all(from c in Character, where: c.story_id == ^story_id, select: c.id)
    totals_query(ids)
  end

  defp totals_query([]), do: %{}

  defp totals_query(ids) do
    Repo.all(
      from e in Entry,
        where: e.character_id in ^ids,
        group_by: e.character_id,
        select:
          {e.character_id,
           sum(fragment("CASE WHEN ? = 'award' THEN ? ELSE 0 END", e.kind, e.amount)),
           sum(fragment("CASE WHEN ? = 'spend' THEN ? ELSE 0 END", e.kind, e.amount))}
    )
    |> Map.new(fn {id, earned, spent} ->
      earned = to_int(earned)
      spent = to_int(spent)
      {id, %{earned: earned, spent: spent, available: earned - spent}}
    end)
  end

  defp empty_totals, do: %{earned: 0, spent: 0, available: 0}

  defp to_int(nil), do: 0
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n

  @doc "The XP log of a character, newest first."
  def list_entries(%Character{id: id}) do
    Repo.all(
      from e in Entry,
        where: e.character_id == ^id,
        order_by: [desc: e.inserted_at, desc: e.id],
        preload: [:author]
    )
  end

  @doc "The latest XP log entries of a whole GDR, newest first."
  def list_story_entries(story_id, limit \\ 50) do
    Repo.all(
      from e in Entry,
        where: e.story_id == ^story_id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit,
        preload: [:author, :character]
    )
  end

  @doc "A human readable message for the XP errors."
  def error_message(:unauthorized), do: "You are not allowed to do that."

  def error_message(:invalid_amount),
    do: "The amount must be a non-zero whole number (max #{@max_award})."

  def error_message(:reason_required), do: "Explain why the XP is awarded."
  def error_message(:insufficient_xp), do: "Not enough XP available."
  def error_message(:cannot_play), do: "The character cannot play right now."
  def error_message(:not_found), do: "That sheet item does not exist."
  def error_message(:not_purchasable), do: "That item cannot be raised with XP."
  def error_message(:at_max), do: "That item is already at its maximum."
  def error_message(:invalid_formula), do: "The XP cost formula of this GDR is invalid."
  def error_message(_), do: "The XP could not be updated."

  defp lock_character!(%Character{id: id}) do
    Repo.one!(from c in Character, where: c.id == ^id, select: c.id, lock: "FOR UPDATE")
  end

  defp insert_entry!(character, attrs) do
    %Entry{story_id: character.story_id, character_id: character.id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  defp story_of(%Character{story: %Story{} = story}), do: story
  defp story_of(%Character{story_id: story_id}), do: Stories.get_story(story_id)
end
