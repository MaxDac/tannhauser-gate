defmodule TannhauserGate.Esiti do
  @moduledoc """
  Esiti ("outcomes"), the `:esiti` optional module: players file action
  requests that the masters resolve off the chat.

    * A player files a request (`TannhauserGate.Esiti.Esito`) as one of their
      playable characters: a title, a Markdown body, an optional room or zone
      and optional related characters of the same GDR. The GDR limits the
      requests still waiting for an outcome per character
      (`stories.esiti_max_open`, nil for no limit) and may require a minimum of
      earned XP (`stories.esiti_min_xp`).
    * A master claims it (`open` → `claimed`, or releases it back), the
      requester and the masters talk in its thread
      (`TannhauserGate.Esiti.Message`) while it is open or claimed.
    * A master resolves it with an outcome and optional effects, applied in
      one transaction (all or nothing): a dice roll with the GDR dice system
      (`TannhauserGate.Dice.roll/3`, recorded), XP (`TannhauserGate.Experience`),
      money (`TannhauserGate.Bank.adjust/3`), items (`TannhauserGate.Items.grant/5`,
      items module only) and a tracker change (`TannhauserGate.Trackers.adjust/3`),
      to the requester and optionally to the related characters.
    * The player withdraws it, or a master dismisses it (`closed`).

  Every change is broadcast as `{:esiti, event, esito}` on `topic/1`; new
  requests and outcomes are also delivered as letters through
  `TannhauserGate.Mailbox` (to "The masters" and from "The masters").
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.{Bank, Characters, Dice, Experience, Items, Mailbox, Repo, Stories}
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Esiti.{Esito, Message}
  alias TannhauserGate.Stories.{Location, Story}
  alias TannhauserGate.Trackers
  alias TannhauserGate.Zones.Zone

  @pubsub TannhauserGate.PubSub
  @masters_name "The masters"
  @max_related 10

  def topic(story_id), do: "esiti:story:#{story_id}"

  def subscribe(story_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(story_id))

  defp broadcast({:ok, %Esito{} = esito} = result, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(esito.story_id), {:esiti, event, esito})
    result
  end

  defp broadcast(result, _event), do: result

  @doc "Whether the esiti module is enabled for the story (or story id)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :esiti)
  def enabled?(story_id) when is_integer(story_id), do: enabled?(Stories.get_story(story_id))
  def enabled?(_), do: false

  ## Queries

  @preloads [:character, :location, :zone, :claimed_by, :resolved_by, :related_characters]

  @doc "The esiti filed by the user's characters in the story, newest first."
  def list_user_esiti(%User{id: user_id}, %Story{id: story_id}) do
    Repo.all(
      from e in Esito,
        join: c in assoc(e, :character),
        where: e.story_id == ^story_id and c.user_id == ^user_id and not c.is_npc,
        order_by: [desc: e.inserted_at, desc: e.id],
        preload: ^@preloads
    )
  end

  @doc """
  The esiti of the story for the master queue. `status` filters by status
  (`"active"` for open and claimed, `"mine"` for those claimed by `user`,
  anything else for all). Active requests come first, oldest first.
  """
  def list_queue(%Story{id: story_id}, status \\ "active", user \\ nil) do
    from(e in Esito,
      where: e.story_id == ^story_id,
      order_by: [
        asc: fragment("CASE ? WHEN 'open' THEN 0 WHEN 'claimed' THEN 1 ELSE 2 END", e.status),
        asc: e.inserted_at,
        asc: e.id
      ],
      preload: ^@preloads
    )
    |> filter_status(status, user)
    |> Repo.all()
  end

  defp filter_status(query, "active", _user),
    do: where(query, [e], e.status in ^Esito.active_statuses())

  defp filter_status(query, "mine", %User{id: id}),
    do: where(query, [e], e.status == "claimed" and e.claimed_by_id == ^id)

  defp filter_status(query, status, _user)
       when status in ["open", "claimed", "resolved", "closed"],
       do: where(query, [e], e.status == ^status)

  defp filter_status(query, _status, _user), do: query

  @doc "The number of esiti per status in the story (`%{\"open\" => n, ...}`)."
  def status_counts(%Story{id: story_id}) do
    Repo.all(
      from e in Esito,
        where: e.story_id == ^story_id,
        group_by: e.status,
        select: {e.status, count(e.id)}
    )
    |> Map.new()
  end

  @doc "The number of requests waiting for a master (status `open`)."
  def open_count(%Story{id: story_id} = story) do
    if enabled?(story) do
      Repo.aggregate(
        from(e in Esito, where: e.story_id == ^story_id and e.status == "open"),
        :count
      )
    else
      0
    end
  end

  def open_count(_), do: 0

  @doc "An esito of the story (`id` may be a string) with its associations, or nil."
  def get_esito(%Story{id: story_id}, id) do
    case parse_id(id) do
      nil -> nil
      id -> Esito |> Repo.get_by(id: id, story_id: story_id) |> Repo.preload(@preloads)
    end
  end

  @doc "The thread of an esito, oldest first."
  def list_messages(%Esito{id: id}) do
    Repo.all(
      from m in Message,
        where: m.esito_id == ^id,
        order_by: [asc: m.inserted_at, asc: m.id],
        preload: [:character]
    )
  end

  ## Permissions

  @doc "Whether the user owns the requesting character."
  def owner?(%User{id: user_id}, %Esito{} = esito) do
    character = esito_character(esito)
    character.user_id == user_id and not character.is_npc
  end

  def owner?(_, _), do: false

  @doc "Whether the user can read the esito: its owner and the masters."
  def can_view?(user, %Story{} = story, %Esito{} = esito),
    do: Stories.master?(user, story) or owner?(user, esito)

  @doc "Whether the user can post in the thread: owner or master, while it is active."
  def can_post?(user, %Story{} = story, %Esito{} = esito),
    do: Esito.active?(esito) and can_view?(user, story, esito)

  ## Filing

  def change_esito(attrs \\ %{}), do: Esito.changeset(%Esito{}, attrs)

  @doc """
  The characters the user can file requests as: their own playable player
  characters in the story.
  """
  def requester_characters(%User{} = user, %Story{} = story) do
    user |> Characters.list_user_characters(story.id) |> Enum.filter(&Characters.can_play?/1)
  end

  @doc """
  Checks the GDR limits for a new request of the character: `:ok`,
  `{:error, :too_many_open}` or `{:error, :not_enough_xp}`.
  """
  def check_limits(%Story{} = story, %Character{} = character) do
    cond do
      is_integer(story.esiti_max_open) and active_count(character) >= story.esiti_max_open ->
        {:error, :too_many_open}

      is_integer(story.esiti_min_xp) and Experience.totals(character).earned < story.esiti_min_xp ->
        {:error, :not_enough_xp}

      true ->
        :ok
    end
  end

  defp active_count(%Character{id: id}) do
    Repo.aggregate(
      from(e in Esito, where: e.character_id == ^id and e.status in ^Esito.active_statuses()),
      :count
    )
  end

  @doc """
  Files a request. `attrs` (string keys): `"character_id"`, `"title"`,
  `"body"`, the optional `"location_id"` or `"zone_id"` and
  `"related_ids"` (characters of the same GDR). Returns `{:ok, esito}`,
  `{:error, changeset}` or `{:error, reason}`.
  """
  def create_esito(%User{} = user, %Story{} = story, attrs) do
    with :ok <- check_enabled(story),
         %Character{} = character <-
           find_by_id(requester_characters(user, story), attrs["character_id"]) ||
             {:error, :character_not_found},
         {:ok, location_id} <- fetch_location_id(story, attrs["location_id"]),
         {:ok, zone_id} <- fetch_zone_id(story, attrs["zone_id"]),
         {:ok, related} <- fetch_related(story, character, attrs["related_ids"]) do
      Repo.transaction(fn ->
        # Serialise the requests of the character so the limit holds.
        Repo.one!(from c in Character, where: c.id == ^character.id, lock: "FOR UPDATE")

        with :ok <- check_limits(story, character),
             {:ok, esito} <-
               %Esito{
                 story_id: story.id,
                 character_id: character.id,
                 user_id: user.id,
                 location_id: location_id,
                 zone_id: zone_id,
                 status: "open"
               }
               |> Esito.changeset(attrs)
               |> Repo.insert() do
          Repo.insert_all(
            "esito_characters",
            Enum.map(related, &%{esito_id: esito.id, character_id: &1.id})
          )

          Repo.preload(esito, @preloads)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> broadcast(:created)
      |> tap(&notify_masters(&1, user, story))
    end
  end

  defp fetch_location_id(_story, id) when id in [nil, ""], do: {:ok, nil}

  defp fetch_location_id(%Story{id: story_id}, id) do
    with id when is_integer(id) <- parse_id(id),
         true <- Repo.exists?(from l in Location, where: l.id == ^id and l.story_id == ^story_id) do
      {:ok, id}
    else
      _ -> {:error, :location_not_found}
    end
  end

  defp fetch_zone_id(_story, id) when id in [nil, ""], do: {:ok, nil}

  defp fetch_zone_id(%Story{id: story_id}, id) do
    with id when is_integer(id) <- parse_id(id),
         true <- Repo.exists?(from z in Zone, where: z.id == ^id and z.story_id == ^story_id) do
      {:ok, id}
    else
      _ -> {:error, :zone_not_found}
    end
  end

  defp fetch_related(_story, _character, ids) when ids in [nil, "", []], do: {:ok, []}

  defp fetch_related(%Story{id: story_id}, %Character{id: own_id}, ids) do
    ids = ids |> List.wrap() |> Enum.map(&parse_id/1)

    cond do
      Enum.any?(ids, &is_nil/1) ->
        {:error, :character_not_found}

      true ->
        ids = ids |> Enum.uniq() |> Enum.reject(&(&1 == own_id))

        found =
          Repo.all(from c in Character, where: c.id in ^ids and c.story_id == ^story_id)

        cond do
          length(found) != length(ids) -> {:error, :character_not_found}
          length(found) > @max_related -> {:error, :too_many_related}
          true -> {:ok, found}
        end
    end
  end

  # A letter from the requester to "The masters" (mailbox notification).
  defp notify_masters({:ok, esito}, user, story) do
    Mailbox.send_message(user, story, %{
      "sender" => to_string(esito.character_id),
      "recipient" => Mailbox.masters(),
      "subject" => String.slice("New esito: #{esito.title}", 0, 200),
      "body" =>
        "#{esito.character.name} filed a new esito request.\n\n" <>
          "Open it: /g/#{story.id}/esiti/#{esito.id}"
    })
  end

  defp notify_masters(_, _, _), do: :ok

  ## Thread

  def change_message(attrs \\ %{}), do: Message.changeset(%Message{}, attrs)

  @doc """
  Posts in the thread of an active esito. The requester's owner writes as
  its character; masters write as "The masters", or with their name when
  `attrs["as"]` is `"self"`.
  """
  def post_message(%User{} = user, %Story{} = story, %Esito{} = esito, attrs) do
    with :ok <- check_esito(story, esito),
         :ok <- check_enabled(story),
         true <- can_view?(user, story, esito) || {:error, :unauthorized},
         true <- Esito.active?(esito) || {:error, :not_active} do
      author =
        cond do
          owner?(user, esito) ->
            character = esito_character(esito)
            %{character_id: character.id, author_name: character.name, from_masters: false}

          attrs["as"] == "self" ->
            %{character_id: nil, author_name: "#{user.username} (master)", from_masters: true}

          true ->
            %{character_id: nil, author_name: @masters_name, from_masters: true}
        end

      %Message{esito_id: esito.id, user_id: user.id}
      |> struct(author)
      |> Message.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          broadcast({:ok, esito}, :message)
          {:ok, message}

        error ->
          error
      end
    end
  end

  ## Status changes

  @doc "A master claims an open esito."
  def claim(%User{} = user, %Story{} = story, %Esito{} = esito) do
    transition(user, story, esito, ["open"], :claimed, fn _ ->
      %{status: "claimed", claimed_by_id: user.id, claimed_at: now()}
    end)
  end

  @doc "A master puts a claimed esito back in the queue."
  def release(%User{} = user, %Story{} = story, %Esito{} = esito) do
    transition(user, story, esito, ["claimed"], :released, fn _ ->
      %{status: "open", claimed_by_id: nil, claimed_at: nil}
    end)
  end

  @doc "A master dismisses an active esito (status `closed`)."
  def dismiss(%User{} = user, %Story{} = story, %Esito{} = esito) do
    transition(user, story, esito, Esito.active_statuses(), :closed, fn _ ->
      %{status: "closed", closed_at: now()}
    end)
  end

  @doc "The requester's owner withdraws an active esito (status `closed`)."
  def withdraw(%User{} = user, %Story{} = story, %Esito{} = esito) do
    with :ok <- check_esito(story, esito),
         :ok <- check_enabled(story),
         true <- owner?(user, esito) || {:error, :unauthorized} do
      update_status(esito, Esito.active_statuses(), fn _ ->
        %{status: "closed", closed_at: now()}
      end)
      |> broadcast(:closed)
    end
  end

  defp transition(user, story, esito, from, event, fun) do
    with :ok <- check_esito(story, esito),
         :ok <- check_enabled(story),
         true <- Stories.master?(user, story) || {:error, :unauthorized} do
      esito |> update_status(from, fun) |> broadcast(event)
    end
  end

  # Updates the esito under a row lock when its current status is in `from`.
  defp update_status(%Esito{id: id}, from, fun) do
    Repo.transaction(fn ->
      current = Repo.one(from e in Esito, where: e.id == ^id, lock: "FOR UPDATE")

      if current && current.status in from do
        current
        |> Ecto.Changeset.change(fun.(current))
        |> Repo.update!()
        |> Repo.preload(@preloads)
      else
        Repo.rollback(:invalid_status)
      end
    end)
  end

  ## Resolution

  @doc """
  A master resolves an active esito: `attrs` (string keys) holds the
  `"outcome"` (Markdown, required) and the optional effects:

    * `"roll"` (`"true"`) with `"dice"` (a `TannhauserGate.Dice.roll/3`
      request: `"items"`, `"modifier"`, `"difficulty"`, `"expression"`,
      `"label"`) rolled for the requester;
    * `"xp"` (awarded with the reason "Esito: <title>");
    * `"money"` (a master adjustment, negative to take money);
    * `"item_id"` and `"item_quantity"` (items module only);
    * `"tracker"` (slug), `"tracker_delta"` and, for trackers with damage
      types, `"tracker_damage_type"`;
    * `"also_related"` (`"true"`): the XP, money, item and tracker effects
      also apply to the related characters.

  Everything happens in one transaction: if any effect fails (e.g. not
  enough money to take, an unknown item) nothing is applied and the esito
  stays as it was. A letter with the outcome is sent from "The masters" to
  the requester. `opts` are passed to `Dice.roll/3` (e.g. `:rng`).
  """
  def resolve(%User{} = user, %Story{} = story, %Esito{} = esito, attrs, opts \\ []) do
    outcome = attrs |> Map.get("outcome", "") |> to_string() |> String.trim()

    with :ok <- check_esito(story, esito),
         :ok <- check_enabled(story),
         true <- Stories.master?(user, story) || {:error, :unauthorized},
         true <- outcome != "" || {:error, :outcome_required},
         true <- String.length(outcome) <= 10_000 || {:error, :outcome_too_long},
         {:ok, effects} <- parse_effects(story, attrs) do
      esito = Repo.preload(esito, [:character, :related_characters])
      requester = esito.character

      targets =
        if effects.also_related,
          do: [requester | esito.related_characters],
          else: [requester]

      Repo.transaction(fn ->
        current = Repo.one(from e in Esito, where: e.id == ^esito.id, lock: "FOR UPDATE")
        unless current && Esito.active?(current), do: Repo.rollback(:invalid_status)

        dice = roll_dice(story, requester, effects, opts)
        note = String.slice("Esito: #{esito.title}", 0, 200)
        Enum.each(targets, &apply_effects!(&1, user, effects, note))

        current
        |> Ecto.Changeset.change(
          status: "resolved",
          outcome: outcome,
          dice_result: dice,
          effects: effects_summary(effects, targets),
          resolved_by_id: user.id,
          resolved_at: now(),
          claimed_by_id: current.claimed_by_id || user.id,
          claimed_at: current.claimed_at || now()
        )
        |> Repo.update!()
        |> Repo.preload(@preloads)
      end)
      |> broadcast(:resolved)
      |> tap(&notify_outcome(&1, user, story))
    end
  end

  defp parse_effects(story, attrs) do
    items? = Items.enabled?(story)

    with {:ok, xp} <- parse_int(attrs["xp"], :invalid_xp),
         {:ok, money} <- parse_int(attrs["money"], :invalid_money),
         {:ok, item_qty} <- parse_int(attrs["item_quantity"], :invalid_quantity),
         {:ok, tracker_delta} <- parse_int(attrs["tracker_delta"], :invalid_tracker_delta) do
      item_id = if items?, do: blank_to_nil(attrs["item_id"])
      tracker = blank_to_nil(attrs["tracker"])

      cond do
        item_id && item_qty <= 0 ->
          {:error, :invalid_quantity}

        tracker && tracker_delta == 0 ->
          {:error, :invalid_tracker_delta}

        true ->
          {:ok,
           %{
             roll: attrs["roll"] in ["true", true],
             dice: attrs["dice"] || %{},
             xp: xp,
             money: money,
             item_id: item_id,
             item_quantity: item_qty,
             tracker: tracker,
             tracker_delta: tracker_delta,
             damage_type: blank_to_nil(attrs["tracker_damage_type"]),
             also_related: attrs["also_related"] in ["true", true]
           }}
      end
    end
  end

  defp roll_dice(_story, _character, %{roll: false}, _opts), do: nil

  defp roll_dice(story, character, %{dice: request}, opts) do
    case Dice.roll(character, request, Keyword.put(opts, :story, story)) do
      {:ok, result} -> result
      {:error, reason} -> Repo.rollback({:dice, reason})
    end
  end

  defp apply_effects!(character, user, effects, note) do
    with :ok <- if_set(effects.xp, &Experience.award(user, character, &1, note)),
         :ok <- if_set(effects.money, &Bank.adjust(character, &1, note)),
         :ok <-
           if_set(
             effects.item_id,
             &Items.grant(character, &1, effects.item_quantity, user, note)
           ),
         :ok <-
           if_set(effects.tracker, fn slug ->
             delta =
               if effects.damage_type,
                 do: {effects.damage_type, effects.tracker_delta},
                 else: effects.tracker_delta

             Trackers.adjust(character, slug, delta)
           end) do
      :ok
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp if_set(value, _fun) when value in [nil, 0], do: :ok

  defp if_set(value, fun) do
    case fun.(value) do
      {:ok, _} -> :ok
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_effect}
      {:error, _} = error -> error
    end
  end

  defp effects_summary(effects, targets) do
    item =
      if effects.item_id do
        case Repo.get(TannhauserGate.Items.Item, parse_id(effects.item_id)) do
          nil -> nil
          item -> %{"name" => item.name, "quantity" => effects.item_quantity}
        end
      end

    tracker =
      if effects.tracker do
        %{
          "name" => tracker_name(targets, effects.tracker),
          "delta" => effects.tracker_delta,
          "damage_type" => effects.damage_type
        }
      end

    %{
      "targets" => Enum.map(targets, & &1.name),
      "xp" => effects.xp,
      "money" => effects.money,
      "item" => item,
      "tracker" => tracker
    }
  end

  defp tracker_name([character | _], slug) do
    case Trackers.get(character, slug) do
      %{tracker: tracker} -> tracker.name
      _ -> slug
    end
  end

  # A letter from "The masters" to the requester with the outcome.
  defp notify_outcome({:ok, esito}, user, story) do
    Mailbox.send_message(user, story, %{
      "sender" => Mailbox.masters(),
      "recipient" => to_string(esito.character_id),
      "subject" => String.slice("Esito resolved: #{esito.title}", 0, 200),
      "body" =>
        String.slice(esito.outcome, 0, 15_000) <>
          effects_text(esito.dice_result, esito.effects) <>
          "\n\nRead it: /g/#{story.id}/esiti/#{esito.id}"
    })
  end

  defp notify_outcome(_, _, _), do: :ok

  defp effects_text(dice, effects) do
    lines =
      [
        dice && "Dice: #{dice["summary"]}"
        | effect_lines(effects)
      ]
      |> Enum.reject(&is_nil/1)

    if lines == [], do: "", else: "\n\n" <> Enum.join(lines, "\n")
  end

  @doc "Human readable lines for the recorded effects of a resolved esito."
  def effect_lines(nil), do: []

  def effect_lines(effects) do
    [
      effects["xp"] not in [nil, 0] && "XP: #{signed(effects["xp"])}",
      effects["money"] not in [nil, 0] && "Money: #{signed(effects["money"])}",
      effects["item"] && "Item: #{effects["item"]["name"]} × #{effects["item"]["quantity"]}",
      effects["tracker"] &&
        "#{effects["tracker"]["name"]}: #{signed(effects["tracker"]["delta"])}" <>
          if(effects["tracker"]["damage_type"],
            do: " (#{effects["tracker"]["damage_type"]})",
            else: ""
          )
    ]
    |> Enum.filter(&is_binary/1)
    |> then(fn
      [] -> []
      lines -> lines ++ ["Applied to: #{Enum.join(effects["targets"] || [], ", ")}"]
    end)
  end

  defp signed(n) when is_integer(n) and n > 0, do: "+#{n}"
  defp signed(n), do: to_string(n)

  ## Labels

  def status_label("open"), do: "Open"
  def status_label("claimed"), do: "In progress"
  def status_label("resolved"), do: "Resolved"
  def status_label("closed"), do: "Closed"
  def status_label(other), do: other

  def error_message(:module_disabled), do: "Esiti are not enabled in this GDR."
  def error_message(:unauthorized), do: "You can't do that with this esito."
  def error_message(:esito_not_found), do: "That esito does not exist in this GDR."
  def error_message(:character_not_found), do: "That character can't take part in this esito."
  def error_message(:location_not_found), do: "That room does not exist in this GDR."
  def error_message(:zone_not_found), do: "That zone does not exist in this GDR."
  def error_message(:too_many_related), do: "Pick at most #{@max_related} related characters."

  def error_message(:too_many_open),
    do: "This character already has the maximum number of open esiti."

  def error_message(:not_enough_xp), do: "This character does not have enough XP to file esiti."
  def error_message(:invalid_status), do: "This esito has changed in the meantime."
  def error_message(:not_active), do: "This esito is no longer open."
  def error_message(:outcome_required), do: "Write the outcome."
  def error_message(:outcome_too_long), do: "The outcome is too long."
  def error_message(:invalid_xp), do: "The XP must be a whole number."
  def error_message(:invalid_money), do: "The money must be a whole number."
  def error_message(:invalid_quantity), do: "Enter a positive item quantity."
  def error_message(:invalid_tracker_delta), do: "Enter a non-zero tracker change."
  def error_message(:invalid_effect), do: "One of the effects could not be applied."
  def error_message({:dice, reason}), do: "Dice: " <> Dice.error_message(reason)

  def error_message(:insufficient_funds),
    do: "A character does not have enough money to take."

  def error_message(:insufficient_xp), do: "A character does not have enough XP to take."
  def error_message(:invalid_amount), do: "The XP must be between -1000 and 1000."
  def error_message(:item_not_found), do: Items.error_message(:item_not_found)
  def error_message(:not_found), do: "That tracker does not exist."
  def error_message(reason) when is_atom(reason), do: Trackers.error_message(reason)
  def error_message(_), do: "Something went wrong."

  ## Helpers

  defp check_enabled(story),
    do: if(enabled?(story), do: :ok, else: {:error, :module_disabled})

  defp check_esito(%Story{id: story_id}, %Esito{story_id: story_id}), do: :ok
  defp check_esito(_, _), do: {:error, :esito_not_found}

  defp esito_character(%Esito{character: %Character{} = character}), do: character
  defp esito_character(%Esito{} = esito), do: Repo.preload(esito, :character).character

  defp find_by_id(characters, id) do
    id = parse_id(id)
    Enum.find(characters, &(&1.id == id))
  end

  defp parse_int(value, _error) when value in [nil, ""], do: {:ok, 0}
  defp parse_int(value, _error) when is_integer(value), do: {:ok, value}

  defp parse_int(value, error) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when abs(int) <= 1_000_000 -> {:ok, int}
      _ -> {:error, error}
    end
  end

  defp parse_int(_, error), do: {:error, error}

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

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
