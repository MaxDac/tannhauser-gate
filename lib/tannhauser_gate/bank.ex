defmodule TannhauserGate.Bank do
  @moduledoc """
  The economy of a GDR: jobs defined by the game master, periodic pay,
  transfers between characters and game master balance adjustments.

  Every balance change is recorded in `bank_transactions`.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TannhauserGate.Bank.{Job, Transaction}
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories.Story

  ## Jobs

  def list_jobs(%Story{id: story_id}) do
    Repo.all(from j in Job, where: j.story_id == ^story_id, order_by: [asc: j.name])
  end

  def get_job!(%Story{id: story_id}, id), do: Repo.get_by!(Job, id: id, story_id: story_id)

  def create_job(%Story{} = story, attrs) do
    %Job{story_id: story.id} |> Job.changeset(attrs) |> Repo.insert()
  end

  def update_job(%Job{} = job, attrs), do: job |> Job.changeset(attrs) |> Repo.update()

  def delete_job(%Job{} = job), do: Repo.delete(job)

  def change_job(%Job{} = job, attrs \\ %{}), do: Job.changeset(job, attrs)

  @doc """
  Gives the character a job of its own story (or none when `job_id` is blank).
  The pay clock starts now.
  """
  def set_job(%Character{} = character, job_id) when job_id in [nil, ""] do
    character |> Ecto.Changeset.change(job_id: nil, last_paid_at: nil) |> Repo.update()
  end

  def set_job(%Character{} = character, job_id) do
    case Repo.get_by(Job, id: job_id, story_id: character.story_id) do
      nil ->
        {:error, :job_not_found}

      job ->
        character
        |> Ecto.Changeset.change(job_id: job.id, last_paid_at: now())
        |> Repo.update()
    end
  end

  ## Pay

  @doc """
  Credits the pay of every character whose pay interval has elapsed.

  Returns the number of characters paid. Safe to call repeatedly: a character
  is only paid once per elapsed interval.
  """
  def pay_due(now \\ now()) do
    from(c in Character,
      join: j in assoc(c, :job),
      join: s in assoc(c, :story),
      where: j.pay > 0,
      where:
        is_nil(c.last_paid_at) or
          fragment(
            "? <= ? - (? * interval '1 hour')",
            c.last_paid_at,
            type(^now, :utc_datetime),
            s.pay_interval_hours
          ),
      select: c.id
    )
    |> Repo.all()
    |> Enum.count(fn id -> match?({:ok, :paid}, pay_character(id, now)) end)
  end

  defp pay_character(id, now) do
    Repo.transaction(fn ->
      character =
        Repo.one(
          from c in Character,
            where: c.id == ^id,
            lock: "FOR UPDATE",
            preload: [:job, :story]
        )

      with %{job: %Job{pay: pay}, story: story} when pay > 0 <- character,
           true <- due?(character, story, now) do
        credit!(character, pay)

        Repo.insert!(%Transaction{
          story_id: story.id,
          to_character_id: character.id,
          amount: pay,
          kind: "pay",
          note: character.job.name
        })

        character |> Ecto.Changeset.change(last_paid_at: now) |> Repo.update!()
        :paid
      else
        _ -> Repo.rollback(:not_due)
      end
    end)
  end

  defp due?(%{last_paid_at: nil}, _story, _now), do: true

  defp due?(%{last_paid_at: last}, story, now),
    do: DateTime.diff(now, last, :second) >= story.pay_interval_hours * 3600

  ## Transfers and adjustments

  @doc """
  Moves `amount` from `from` to the character `to_id` of the same story.
  """
  def transfer(%Character{} = from, to_id, amount, note \\ nil) do
    with {:ok, amount} <- parse_amount(amount),
         %Character{} = to <- find_character(from.story_id, to_id),
         true <- to.id != from.id || {:error, :same_character} do
      Multi.new()
      |> Multi.run(:lock, fn repo, _ -> lock_in_order(repo, [from.id, to.id]) end)
      |> Multi.run(:debit, fn repo, _ ->
        {count, _} =
          repo.update_all(
            from(c in Character, where: c.id == ^from.id and c.balance >= ^amount),
            inc: [balance: -amount]
          )

        if count == 1, do: {:ok, amount}, else: {:error, :insufficient_funds}
      end)
      |> Multi.update_all(:credit, from(c in Character, where: c.id == ^to.id),
        inc: [balance: amount]
      )
      |> Multi.insert(:transaction, %Transaction{
        story_id: from.story_id,
        from_character_id: from.id,
        to_character_id: to.id,
        amount: amount,
        kind: "transfer",
        note: clean_note(note)
      })
      |> Repo.transaction()
      |> case do
        {:ok, %{transaction: transaction}} -> {:ok, transaction}
        {:error, _step, reason, _} -> {:error, reason}
      end
    else
      nil -> {:error, :recipient_not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Game master adjustment: adds (or removes, if negative) money to a character.
  The balance never goes below zero.
  """
  def adjust(%Character{} = character, amount, note \\ nil) do
    with {:ok, amount} <- parse_amount(amount, allow_negative: true) do
      Multi.new()
      |> Multi.run(:update, fn repo, _ ->
        {count, _} =
          repo.update_all(
            from(c in Character, where: c.id == ^character.id and c.balance + ^amount >= 0),
            inc: [balance: amount]
          )

        if count == 1, do: {:ok, amount}, else: {:error, :insufficient_funds}
      end)
      |> Multi.insert(:transaction, %Transaction{
        story_id: character.story_id,
        to_character_id: character.id,
        amount: amount,
        kind: "adjustment",
        note: clean_note(note)
      })
      |> Repo.transaction()
      |> case do
        {:ok, %{transaction: transaction}} -> {:ok, transaction}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  @doc "Recent transactions involving a character, newest first."
  def list_transactions(%Character{id: id}, limit \\ 50) do
    Repo.all(
      from t in Transaction,
        where: t.from_character_id == ^id or t.to_character_id == ^id,
        order_by: [desc: t.inserted_at, desc: t.id],
        limit: ^limit,
        preload: [:from_character, :to_character]
    )
  end

  @doc "Recipients a character can send money to: the other characters of its GDR."
  def list_recipients(%Character{id: id, story_id: story_id}) do
    Repo.all(
      from c in Character,
        where: c.story_id == ^story_id and c.id != ^id,
        order_by: [asc: c.name]
    )
  end

  def error_message(:insufficient_funds), do: "Not enough funds."
  def error_message(:invalid_amount), do: "Enter a whole amount greater than zero."
  def error_message(:recipient_not_found), do: "That character does not exist in this GDR."
  def error_message(:same_character), do: "You can't send money to yourself."
  def error_message(:job_not_found), do: "That job does not exist."
  def error_message(_), do: "Something went wrong."

  ## Helpers

  defp lock_in_order(repo, ids) do
    repo.all(
      from c in Character, where: c.id in ^ids, order_by: c.id, lock: "FOR UPDATE", select: c.id
    )

    {:ok, ids}
  end

  defp credit!(%Character{id: id}, amount) do
    Repo.update_all(from(c in Character, where: c.id == ^id), inc: [balance: amount])
  end

  defp find_character(story_id, id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> Repo.get_by(Character, id: int, story_id: story_id)
      _ -> nil
    end
  end

  defp parse_amount(amount, opts \\ [])

  defp parse_amount(amount, opts) when is_binary(amount) do
    case Integer.parse(String.trim(amount)) do
      {int, ""} -> parse_amount(int, opts)
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_amount(amount, opts) when is_integer(amount) do
    cond do
      abs(amount) > 1_000_000_000 -> {:error, :invalid_amount}
      amount > 0 -> {:ok, amount}
      amount < 0 and opts[:allow_negative] -> {:ok, amount}
      true -> {:error, :invalid_amount}
    end
  end

  defp parse_amount(_, _), do: {:error, :invalid_amount}

  defp clean_note(nil), do: nil

  defp clean_note(note) do
    case note |> String.trim() |> String.slice(0, 200) do
      "" -> nil
      note -> note
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
