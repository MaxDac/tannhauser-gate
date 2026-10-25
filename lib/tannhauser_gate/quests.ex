defmodule TannhauserGate.Quests do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  The quest registry, the `:quests` optional module.

  Masters record the quests (or scenes) they ran
  (`TannhauserGate.Quests.Quest`): a title, a Markdown summary, the date, the
  room, the master, a visibility (`public` or `masters` only) and an
  optional chat-log range. Each participant (`TannhauserGate.Quests.Participant`),
  a character of the GDR, gets rewards: XP, money and an item (items module).

  `apply_rewards/3` hands out every reward in one transaction (all or
  nothing) and marks the quest as rewarded, so it can't happen twice; after
  that the participants are frozen.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.{Bank, Experience, Items, Repo, Stories}
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Quests.{Participant, Quest}
  alias TannhauserGate.Stories.{Location, Story}

  @pubsub TannhauserGate.PubSub

  def topic(story_id), do: "quests:story:#{story_id}"

  defp broadcast({:ok, %Quest{} = quest} = result, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(quest.story_id), {:quests, event, quest})
    result
  end

  defp broadcast(result, _event), do: result

  @doc "Whether the quests module is enabled for the story (or story id)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :quests)
  def enabled?(story_id) when is_integer(story_id), do: enabled?(Stories.get_story(story_id))
  def enabled?(_), do: false

  ## Queries

  @doc """
  The quests of the story the user can see, newest first: every quest for
  the masters, the public ones for everyone else.
  """
  def list_quests(%Story{id: story_id} = story, user) do
    from(q in Quest,
      where: q.story_id == ^story_id,
      order_by: [desc: q.held_on, desc: q.id],
      preload: ^participant_preloads()
    )
    |> visible_to(story, user)
    |> Repo.all()
  end

  defp participant_preloads do
    participants = from p in Participant, join: c in assoc(p, :character), order_by: c.name

    [:location, :master, :rewards_applied_by, participants: {participants, [:character, :item]}]
  end

  defp visible_to(query, story, user) do
    if Stories.master?(user, story),
      do: query,
      else: where(query, [q], q.visibility == "public")
  end

  @doc "Whether the user can see the quest."
  def visible?(%Quest{visibility: "public"}, _story, _user), do: true
  def visible?(%Quest{}, story, user), do: Stories.master?(user, story)

  @doc """
  The quests a character took part in that the viewer can see (public ones,
  all for the masters), newest first. Empty when the module is disabled.
  """
  def character_quests(%Character{} = character, viewer) do
    story = Stories.get_story(character.story_id)

    if enabled?(story) do
      from(q in Quest,
        join: p in assoc(q, :participants),
        where: p.character_id == ^character.id and q.story_id == ^character.story_id,
        order_by: [desc: q.held_on, desc: q.id]
      )
      |> visible_to(story, viewer)
      |> Repo.all()
    else
      []
    end
  end

  @doc "A quest of the story (`id` may be a string) with its participants, or nil."
  def get_quest(%Story{id: story_id}, id) do
    case parse_id(id) do
      nil ->
        nil

      id ->
        Quest |> Repo.get_by(id: id, story_id: story_id) |> Repo.preload(participant_preloads())
    end
  end

  ## Quests

  def change_quest(%Quest{} = quest, attrs \\ %{}), do: Quest.changeset(quest, attrs)

  @doc "A master records a quest; they are its master."
  def create_quest(%User{} = user, %Story{} = story, attrs) do
    with :ok <- authorize(user, story) do
      %Quest{story_id: story.id, master_id: user.id}
      |> Quest.changeset(attrs)
      |> validate_location(story)
      |> Repo.insert()
      |> preload()
      |> broadcast(:created)
    end
  end

  @doc "A master updates the quest's details (the participants have their own functions)."
  def update_quest(%User{} = user, %Story{} = story, %Quest{} = quest, attrs) do
    with :ok <- check_quest(story, quest),
         :ok <- authorize(user, story) do
      quest
      |> Quest.changeset(attrs)
      |> validate_location(story)
      |> Repo.update()
      |> preload()
      |> broadcast(:updated)
    end
  end

  @doc "A master deletes a quest (rewards already handed out stay where they are)."
  def delete_quest(%User{} = user, %Story{} = story, %Quest{} = quest) do
    with :ok <- check_quest(story, quest),
         :ok <- authorize(user, story) do
      quest |> Repo.delete() |> broadcast(:deleted)
    end
  end

  defp validate_location(changeset, %Story{id: story_id}) do
    Ecto.Changeset.validate_change(changeset, :location_id, fn :location_id, id ->
      if Repo.exists?(from l in Location, where: l.id == ^id and l.story_id == ^story_id),
        do: [],
        else: [location_id: dgettext_noop("errors", "is not a room of this GDR")]
    end)
  end

  defp preload({:ok, quest}), do: {:ok, Repo.preload(quest, participant_preloads(), force: true)}
  defp preload(error), do: error

  ## Participants

  def change_participant(%Participant{} = participant, attrs \\ %{}),
    do: Participant.changeset(participant, attrs)

  @doc """
  Adds a character of the GDR to the quest with its rewards (`attrs`:
  `"character_id"`, `"xp"`, `"money"`, `"item_id"`, `"item_quantity"`,
  `"note"`). Not allowed once the rewards were handed out.
  """
  def add_participant(%User{} = user, %Story{} = story, %Quest{} = quest, attrs) do
    with :ok <- check_quest(story, quest),
         :ok <- authorize(user, story),
         :ok <- check_not_rewarded(quest),
         %Character{} = character <-
           fetch_character(story, attrs["character_id"]) || {:error, :character_not_found},
         {:ok, item_id} <- fetch_item_id(story, attrs["item_id"]) do
      %Participant{quest_id: quest.id, character_id: character.id, item_id: item_id}
      |> Participant.changeset(attrs)
      |> validate_item_quantity()
      |> Repo.insert()
    end
  end

  @doc "Updates the rewards of a participant (before the rewards are handed out)."
  def update_participant(%User{} = user, %Story{} = story, %Quest{} = quest, id, attrs) do
    with :ok <- check_quest(story, quest),
         :ok <- authorize(user, story),
         :ok <- check_not_rewarded(quest),
         %Participant{} = participant <- get_participant(quest, id) || {:error, :not_found},
         {:ok, item_id} <- fetch_item_id(story, attrs["item_id"]) do
      participant
      |> Participant.changeset(attrs)
      |> Ecto.Changeset.put_change(:item_id, item_id)
      |> validate_item_quantity()
      |> Repo.update()
    end
  end

  @doc "Removes a participant (before the rewards are handed out)."
  def remove_participant(%User{} = user, %Story{} = story, %Quest{} = quest, id) do
    with :ok <- check_quest(story, quest),
         :ok <- authorize(user, story),
         :ok <- check_not_rewarded(quest),
         %Participant{} = participant <- get_participant(quest, id) || {:error, :not_found} do
      Repo.delete(participant)
    end
  end

  defp get_participant(%Quest{id: quest_id}, id) do
    case parse_id(id) do
      nil -> nil
      id -> Repo.get_by(Participant, id: id, quest_id: quest_id)
    end
  end

  defp validate_item_quantity(changeset) do
    item_id = Ecto.Changeset.get_field(changeset, :item_id)
    qty = Ecto.Changeset.get_field(changeset, :item_quantity)

    if item_id && qty < 1,
      do:
        Ecto.Changeset.add_error(
          changeset,
          :item_quantity,
          dgettext_noop("errors", "must be at least 1 for the item")
        ),
      else: changeset
  end

  @doc "The characters that can be added to the quest: those of the GDR not in it yet."
  def participant_candidates(%Story{id: story_id}, %Quest{id: quest_id}) do
    taken = from p in Participant, where: p.quest_id == ^quest_id, select: p.character_id

    Repo.all(
      from c in Character,
        where: c.story_id == ^story_id and c.id not in subquery(taken),
        where: c.approval_status == "approved",
        order_by: [asc: c.name]
    )
  end

  ## Rewards

  @doc """
  Hands out every participant's rewards in one transaction: XP with
  `TannhauserGate.Experience` (reason "Quest: <title>"), money with
  `TannhauserGate.Bank.adjust/3` and items with `TannhauserGate.Items.grant/5`
  (only when the items module is enabled). If anything fails nothing is
  applied. The quest is locked and marked as rewarded in the same
  transaction, so the rewards can't be handed out twice
  (`{:error, :already_rewarded}`).
  """
  def apply_rewards(%User{} = user, %Story{} = story, %Quest{} = quest) do
    with :ok <- check_quest(story, quest),
         :ok <- authorize(user, story) do
      items? = Items.enabled?(story)

      Repo.transaction(fn ->
        current = lock_unrewarded_quest!(quest.id)
        note = String.slice("Quest: #{current.title}", 0, 200)

        participants =
          Repo.all(from p in Participant, where: p.quest_id == ^current.id, preload: [:character])

        Enum.each(participants, &reward!(&1, user, note, items?))

        current
        |> Ecto.Changeset.change(rewards_applied_at: now(), rewards_applied_by_id: user.id)
        |> Repo.update!()
        |> Repo.preload(participant_preloads())
      end)
      |> broadcast(:rewarded)
    end
  end

  defp lock_unrewarded_quest!(id) do
    current = Repo.one(from q in Quest, where: q.id == ^id, lock: "FOR UPDATE")

    cond do
      is_nil(current) -> Repo.rollback(:quest_not_found)
      Quest.rewarded?(current) -> Repo.rollback(:already_rewarded)
      true -> current
    end
  end

  defp reward!(%Participant{character: character} = p, user, note, items?) do
    with :ok <- run_if(p.xp > 0, fn -> Experience.award(user, character, p.xp, note) end),
         :ok <- run_if(p.money > 0, fn -> Bank.adjust(character, p.money, note) end),
         :ok <-
           run_if(items? and not is_nil(p.item_id) and p.item_quantity > 0, fn ->
             Items.grant(character, p.item_id, p.item_quantity, user, note)
           end) do
      :ok
    else
      {:error, %Ecto.Changeset{}} -> Repo.rollback(:invalid_reward)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp run_if(false, _fun), do: :ok

  defp run_if(true, fun) do
    case fun.() do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  ## Labels

  def visibility_label("public"), do: dgettext("domain", "Public")
  def visibility_label("masters"), do: dgettext("domain", "Masters only")
  def visibility_label(other), do: other

  @doc "Query params for the master chat log covering the quest's range, or nil."
  def chat_log_params(%Quest{log_from: nil, log_to: nil}), do: nil

  def chat_log_params(%Quest{} = quest) do
    [
      {"location_id", quest.location_id},
      {"from", quest.log_from && quest.log_from |> DateTime.to_date() |> Date.to_iso8601()},
      {"to", quest.log_to && quest.log_to |> DateTime.to_date() |> Date.to_iso8601()}
    ]
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
  end

  def error_message(:module_disabled),
    do: dgettext("domain", "Quests are not enabled in this GDR.")

  def error_message(:unauthorized), do: dgettext("domain", "Only the masters can do that.")

  def error_message(:quest_not_found),
    do: dgettext("domain", "That quest does not exist in this GDR.")

  def error_message(:character_not_found),
    do: dgettext("domain", "That character does not exist in this GDR.")

  def error_message(:item_not_found), do: Items.error_message(:item_not_found)
  def error_message(:not_found), do: dgettext("domain", "That participant does not exist.")

  def error_message(:already_rewarded),
    do: dgettext("domain", "The rewards of this quest were already handed out.")

  def error_message(:invalid_reward),
    do: dgettext("domain", "One of the rewards could not be applied.")

  def error_message(:invalid_amount),
    do: dgettext("domain", "XP rewards must be between 1 and 1000.")

  def error_message(reason) when is_atom(reason), do: Items.error_message(reason)
  def error_message(_), do: dgettext("domain", "Something went wrong.")

  ## Helpers

  defp authorize(user, story) do
    cond do
      not enabled?(story) -> {:error, :module_disabled}
      not Stories.can?(user, story, :can_manage_esiti_quests) -> {:error, :unauthorized}
      true -> :ok
    end
  end

  defp check_quest(%Story{id: story_id}, %Quest{story_id: story_id}), do: :ok
  defp check_quest(_, _), do: {:error, :quest_not_found}

  defp check_not_rewarded(%Quest{} = quest) do
    current = Repo.get(Quest, quest.id)

    if current && Quest.rewarded?(current),
      do: {:error, :already_rewarded},
      else: :ok
  end

  defp fetch_character(%Story{id: story_id}, id) do
    case parse_id(id) do
      nil -> nil
      id -> Repo.get_by(Character, id: id, story_id: story_id)
    end
  end

  defp fetch_item_id(_story, id) when id in [nil, ""], do: {:ok, nil}

  defp fetch_item_id(%Story{} = story, id) do
    cond do
      not Items.enabled?(story) -> {:ok, nil}
      item = Items.get_item(story, id) -> {:ok, item.id}
      true -> {:error, :item_not_found}
    end
  end

  defp now, do: DateTime.utc_now(:second)

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end
