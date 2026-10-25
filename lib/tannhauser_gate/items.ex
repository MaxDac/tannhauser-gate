defmodule TannhauserGate.Items do
  @moduledoc """
  Items, inventory, equipment and market, the `:items` optional module.

    * **Catalog** (GDR admin): items with a Markdown description, an optional
      image, a category, a base price, an equipment slot with sheet modifiers
      and an optional consumable tracker effect (`TannhauserGate.Items.Item`).
    * **Inventory**: `character_items` stacks (quantity >= 1) with an
      `equipped` flag, one equipped item per slot per character. Non-stackable
      items are held one at a time.
    * **Equipment modifiers** of the equipped items are added to the
      character's effective values in `TannhauserGate.Characters.values_by_slug/1`
      (formulas, tracker maximums, dice pools, periodic actions).
    * **Shops** of the GDR, optionally in a room, list items with an optional
      price override and stock (nil = unlimited). Buying locks the character
      row, decrements the stock with a conditional update, charges the
      character through `TannhauserGate.Bank.charge/4` and fills the
      inventory, all in one transaction.
    * Every grant, removal, gift, purchase, use and (un)equip is recorded in
      the **item log** (`TannhauserGate.Items.Log`).

  Every function scopes ids to the character's (or story's) GDR, and the
  inventory actions return `{:error, :module_disabled}` when the module is
  off. Permission checks (owner vs master) are the callers' job.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Bank
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Items.{CharacterItem, Item, Listing, Log, Shop}
  alias TannhauserGate.Origins
  alias TannhauserGate.Repo
  alias TannhauserGate.Sheet
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.{Location, Story}
  alias TannhauserGate.Trackers

  @max_quantity 10_000

  @doc "Whether the items module is enabled for the story (or story id)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :items)
  def enabled?(story_id) when is_integer(story_id), do: enabled?(Stories.get_story(story_id))
  def enabled?(_), do: false

  ## Catalog

  @doc "The items of a story, by category then name."
  def list_items(%Story{id: story_id}) do
    Repo.all(
      from i in Item,
        where: i.story_id == ^story_id,
        order_by: [asc_nulls_first: i.category, asc: i.name],
        preload: :tracker
    )
  end

  def get_item!(%Story{id: story_id}, id), do: Repo.get_by!(Item, id: id, story_id: story_id)

  @doc "An item of the story (`id` may be a string), or nil."
  def get_item(%Story{id: story_id}, id), do: fetch_item(story_id, id)

  @doc "Creates an item. `image_path` is an already stored image."
  def create_item(%Story{} = story, attrs, image_path \\ nil) do
    %Item{story_id: story.id}
    |> item_changeset(story, attrs)
    |> maybe_put_image(image_path)
    |> Repo.insert()
  end

  def update_item(%Story{} = story, %Item{} = item, attrs, image_path \\ nil) do
    item
    |> item_changeset(story, attrs)
    |> maybe_put_image(image_path)
    |> Repo.update()
  end

  @doc "Deletes an item, its stacks in the inventories and its shop listings."
  def delete_item(%Item{} = item), do: Repo.delete(item)

  def change_item(%Story{} = story, %Item{} = item, attrs \\ %{}),
    do: item_changeset(item, story, attrs)

  def remove_item_image(%Item{} = item), do: item |> Item.image_changeset(nil) |> Repo.update()

  defp item_changeset(item, story, attrs),
    do: Item.changeset(item, attrs, Sheet.slugs(story), Trackers.list_trackers(story))

  defp maybe_put_image(changeset, nil), do: changeset
  defp maybe_put_image(changeset, path), do: Item.image_changeset(changeset, path)

  @doc "The categories used by the story's items."
  def categories(%Story{} = story), do: distinct_values(story, :category)

  @doc "The equipment slots used by the story's items."
  def slots(%Story{} = story), do: distinct_values(story, :slot)

  defp distinct_values(%Story{id: story_id}, field) do
    Repo.all(
      from i in Item,
        where: i.story_id == ^story_id and not is_nil(field(i, ^field)),
        distinct: true,
        select: field(i, ^field),
        order_by: field(i, ^field)
    )
  end

  ## Shops

  @doc "The shops of a story with their room and listings."
  def list_shops(%Story{id: story_id}) do
    Repo.all(
      from s in Shop,
        where: s.story_id == ^story_id,
        order_by: [asc: s.name],
        preload: [:location, listings: :item]
    )
  end

  @doc "The shops located in a room."
  def list_location_shops(%Location{id: location_id, story_id: story_id}) do
    if enabled?(story_id) do
      Repo.all(
        from s in Shop,
          where: s.story_id == ^story_id and s.location_id == ^location_id,
          order_by: [asc: s.name]
      )
    else
      []
    end
  end

  def get_shop!(%Story{id: story_id}, id) do
    Shop
    |> Repo.get_by!(id: id, story_id: story_id)
    |> Repo.preload([:location, listings: :item])
  end

  @doc "A shop of the story (`id` may be a string), or nil."
  def get_shop(%Story{id: story_id}, id) do
    with {:ok, id} <- parse_id(id),
         %Shop{} = shop <- Repo.get_by(Shop, id: id, story_id: story_id) do
      Repo.preload(shop, [:location, listings: :item])
    else
      _ -> nil
    end
  end

  def create_shop(%Story{} = story, attrs) do
    %Shop{story_id: story.id}
    |> Shop.changeset(attrs)
    |> validate_location(story)
    |> Repo.insert()
  end

  def update_shop(%Story{} = story, %Shop{} = shop, attrs) do
    shop |> Shop.changeset(attrs) |> validate_location(story) |> Repo.update()
  end

  def delete_shop(%Shop{} = shop), do: Repo.delete(shop)

  def change_shop(%Shop{} = shop, attrs \\ %{}), do: Shop.changeset(shop, attrs)

  defp validate_location(changeset, %Story{id: story_id}) do
    location_id = Ecto.Changeset.get_field(changeset, :location_id)

    if is_nil(location_id) or
         Repo.exists?(from l in Location, where: l.id == ^location_id and l.story_id == ^story_id),
       do: changeset,
       else: Ecto.Changeset.add_error(changeset, :location_id, "is not a room of this GDR")
  end

  @doc "A listing of a shop of the story, with its shop and item, or nil."
  def get_listing(%Story{id: story_id}, id), do: fetch_listing(story_id, id)

  @doc "Adds an item of the story to a shop."
  def create_listing(%Story{id: story_id} = story, %Shop{story_id: story_id} = shop, attrs) do
    %Listing{shop_id: shop.id}
    |> Listing.changeset(attrs)
    |> validate_listing_item(story)
    |> Repo.insert()
  end

  def update_listing(%Story{} = story, %Listing{} = listing, attrs) do
    listing |> Listing.changeset(attrs) |> validate_listing_item(story) |> Repo.update()
  end

  def delete_listing(%Listing{} = listing), do: Repo.delete(listing)

  def change_listing(%Listing{} = listing, attrs \\ %{}), do: Listing.changeset(listing, attrs)

  defp validate_listing_item(changeset, %Story{id: story_id}) do
    item_id = Ecto.Changeset.get_field(changeset, :item_id)

    if is_nil(item_id) or
         Repo.exists?(from i in Item, where: i.id == ^item_id and i.story_id == ^story_id),
       do: changeset,
       else: Ecto.Changeset.add_error(changeset, :item_id, "is not an item of this GDR")
  end

  ## Inventory

  @doc """
  The inventory of a character (stacks with their item), equipped first;
  empty when the module is disabled.
  """
  def inventory(%Character{id: nil}), do: []

  def inventory(%Character{} = character) do
    if enabled?(story_of(character)) do
      Repo.all(
        from ci in CharacterItem,
          join: i in assoc(ci, :item),
          where: ci.character_id == ^character.id,
          order_by: [desc: ci.equipped, asc_nulls_first: i.category, asc: i.name],
          preload: [item: {i, :tracker}]
      )
    else
      []
    end
  end

  @doc "The equipped items of a character (stacks with their item)."
  def equipped(%Character{} = character),
    do: character |> inventory() |> Enum.filter(& &1.equipped)

  @doc """
  The total modifiers of the character's equipped items per sheet item slug
  (`%{slug => ±N}`); empty when the module is disabled.
  """
  def equipment_modifiers(%Character{id: nil}), do: %{}

  def equipment_modifiers(%Character{} = character) do
    if enabled?(story_of(character)) do
      Repo.all(
        from ci in CharacterItem,
          join: i in assoc(ci, :item),
          where: ci.character_id == ^character.id and ci.equipped and not is_nil(i.slot),
          select: i.modifiers
      )
      |> Origins.sum_bonuses()
    else
      %{}
    end
  end

  @doc "The characters a character can give items to: the other approved characters of its GDR."
  def give_recipients(%Character{id: id, story_id: story_id}) do
    Repo.all(
      from c in Character,
        where: c.story_id == ^story_id and c.id != ^id and c.approval_status == "approved",
        order_by: [asc: c.name, asc: c.id]
    )
  end

  ## Inventory actions

  @doc "Master action: gives `quantity` units of an item of the GDR to a character."
  def grant(%Character{} = character, item_id, quantity, actor, note \\ nil) do
    with {:ok, item, qty} <- prepare(character, item_id, quantity) do
      transaction(fn ->
        lock_characters([character.id])
        add_units!(character.id, item, qty)
        log!(character, item, qty, "grant", actor, note: note)
        %{item: item, quantity: qty}
      end)
    end
  end

  @doc "Master action: removes `quantity` units of an item from a character."
  def remove(%Character{} = character, item_id, quantity, actor, note \\ nil) do
    with {:ok, item, qty} <- prepare(character, item_id, quantity) do
      transaction(fn ->
        lock_characters([character.id])
        take_units!(character.id, item.id, qty)
        log!(character, item, qty, "remove", actor, note: note)
        %{item: item, quantity: qty}
      end)
    end
  end

  @doc """
  Gives `quantity` units of an item from `from` to another approved character
  of the same GDR (`to_id`).
  """
  def give(%Character{} = from, to_id, item_id, quantity, actor) do
    with {:ok, item, qty} <- prepare(from, item_id, quantity),
         {:ok, to} <- fetch_recipient(from, to_id) do
      transaction(fn ->
        lock_characters([from.id, to.id])
        take_units!(from.id, item.id, qty)
        add_units!(to.id, item, qty)
        log!(from, item, qty, "give", actor, target: to)
        %{item: item, quantity: qty, to: to}
      end)
    end
  end

  @doc """
  Uses a consumable: applies its tracker effect with
  `TannhauserGate.Trackers.adjust/3` and consumes one unit when the item says
  so. Returns `{:ok, %{item: item, state: tracker_state}}`.
  """
  def use_item(%Character{} = character, item_id, actor) do
    with {:ok, item, 1} <- prepare(character, item_id, 1),
         true <- Item.usable?(item) || {:error, :not_usable} do
      transaction(fn ->
        lock_characters([character.id])

        consume!(character, item)
        state = apply_effect!(character, item)
        log!(character, item, 1, "use", actor, note: effect_note(item, state))
        %{item: item, state: state}
      end)
    end
  end

  defp consume!(character, %Item{consumed_on_use: true} = item),
    do: take_units!(character.id, item.id, 1)

  defp consume!(character, item), do: owned_row!(character.id, item.id)

  defp apply_effect!(character, item) do
    case Trackers.adjust(character, item.tracker_id, effect_delta(item)) do
      {:ok, state} -> state
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp effect_delta(%Item{effect_damage_type: nil, effect_change: change}), do: change
  defp effect_delta(%Item{effect_damage_type: type, effect_change: change}), do: {type, change}

  defp effect_note(item, state) do
    target = if item.effect_damage_type, do: " (#{item.effect_damage_type})", else: ""
    "#{state.tracker.name}#{target} #{Origins.signed(item.effect_change)}"
  end

  @doc """
  Equips an owned item in its slot, unequipping the item previously equipped
  in the same slot.
  """
  def equip(%Character{} = character, item_id, actor) do
    with {:ok, item, 1} <- prepare(character, item_id, 1),
         true <- Item.equippable?(item) || {:error, :not_equippable} do
      transaction(fn ->
        lock_characters([character.id])
        row = owned_row!(character.id, item.id)

        others =
          Repo.all(
            from ci in CharacterItem,
              join: i in assoc(ci, :item),
              where:
                ci.character_id == ^character.id and ci.equipped and i.slot == ^item.slot and
                  ci.id != ^row.id,
              preload: [item: i]
          )

        Repo.update_all(
          from(ci in CharacterItem, where: ci.id in ^Enum.map(others, & &1.id)),
          set: [equipped: false, updated_at: now()]
        )

        Enum.each(others, &log!(character, &1.item, 1, "unequip", actor))

        equip_row!(row, character, item, actor)

        %{item: item, unequipped: Enum.map(others, & &1.item)}
      end)
    end
  end

  defp equip_row!(%CharacterItem{equipped: true}, _character, _item, _actor), do: :ok

  defp equip_row!(row, character, item, actor) do
    row |> Ecto.Changeset.change(equipped: true) |> Repo.update!()
    log!(character, item, 1, "equip", actor, note: item.slot)
  end

  defp unequip_row!(%CharacterItem{equipped: true} = row, character, item, actor) do
    row |> Ecto.Changeset.change(equipped: false) |> Repo.update!()
    log!(character, item, 1, "unequip", actor)
  end

  defp unequip_row!(_row, _character, _item, _actor), do: :ok

  @doc "Unequips an owned item."
  def unequip(%Character{} = character, item_id, actor) do
    with {:ok, item, 1} <- prepare(character, item_id, 1) do
      transaction(fn ->
        lock_characters([character.id])
        row = owned_row!(character.id, item.id)

        unequip_row!(row, character, item, actor)

        %{item: item}
      end)
    end
  end

  @doc """
  Buys `quantity` units of a shop listing of the character's GDR: in one
  transaction it locks the character row, decrements the stock (when
  limited) with a conditional update, charges the character through
  `TannhauserGate.Bank.charge/4` (ledger note "Bought 2× Medkit at Shop X") and
  adds the items to the inventory. Errors: `:out_of_stock`,
  `:insufficient_funds`, `:not_stackable`, `:listing_not_found`...
  """
  def buy(%Character{} = character, listing_id, quantity, actor) do
    with :ok <- check_enabled(character),
         {:ok, qty} <- parse_quantity(quantity),
         %Listing{} = listing <- fetch_listing(character.story_id, listing_id) || listing_error() do
      %{item: item, shop: shop} = listing
      total = Listing.unit_price(listing) * qty
      note = "Bought #{qty}× #{item.name} at #{shop.name}"

      transaction(fn ->
        lock_characters([character.id])
        take_stock!(listing.id, qty)
        add_units!(character.id, item, qty)

        charge!(character, total, note)

        log!(character, item, qty, "buy", actor, note: "#{shop.name} · #{total}")
        %{item: item, quantity: qty, total: total, shop: shop}
      end)
    end
  end

  defp listing_error, do: {:error, :listing_not_found}

  defp charge!(character, total, note) do
    case Bank.charge(Repo, character, total, note) do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp take_stock!(listing_id, qty) do
    {count, _} =
      Repo.update_all(
        from(l in Listing,
          where: l.id == ^listing_id and (is_nil(l.stock) or l.stock >= ^qty)
        ),
        inc: [stock: -qty],
        set: [updated_at: now()]
      )

    if count != 1, do: Repo.rollback(:out_of_stock)
  end

  ## Log

  @doc """
  The latest item log entries of a story, newest first. Options: `:limit`
  (default 100), `:character_id` (as actor or target).
  """
  def list_logs(%Story{id: story_id}, opts \\ []) do
    query =
      from l in Log,
        where: l.story_id == ^story_id,
        order_by: [desc: l.inserted_at, desc: l.id],
        limit: ^Keyword.get(opts, :limit, 100),
        preload: [:character, :target_character, :user]

    query =
      case opts[:character_id] && parse_id(opts[:character_id]) do
        {:ok, id} -> where(query, [l], l.character_id == ^id or l.target_character_id == ^id)
        _ -> query
      end

    Repo.all(query)
  end

  @doc "A short label for a log action."
  def action_label("grant"), do: "Granted"
  def action_label("remove"), do: "Removed"
  def action_label("give"), do: "Gave"
  def action_label("buy"), do: "Bought"
  def action_label("use"), do: "Used"
  def action_label("equip"), do: "Equipped"
  def action_label("unequip"), do: "Unequipped"
  def action_label(other), do: other

  @doc "A human readable message for the errors of this context."
  def error_message(:module_disabled), do: "Items are not enabled in this GDR."
  def error_message(:item_not_found), do: "That item does not exist in this GDR."
  def error_message(:listing_not_found), do: "That item is not sold here."
  def error_message(:recipient_not_found), do: "That character does not exist in this GDR."
  def error_message(:same_character), do: "You can't give items to yourself."
  def error_message(:invalid_quantity), do: "Enter a quantity between 1 and #{@max_quantity}."
  def error_message(:not_enough_items), do: "Not enough of that item in the inventory."
  def error_message(:not_owned), do: "That item is not in the inventory."
  def error_message(:not_stackable), do: "That item can be held only once."
  def error_message(:not_equippable), do: "That item can't be equipped."
  def error_message(:not_usable), do: "That item can't be used."
  def error_message(:out_of_stock), do: "Not enough stock left."
  def error_message(:insufficient_funds), do: Bank.error_message(:insufficient_funds)
  def error_message(reason), do: Trackers.error_message(reason)

  ## Helpers

  defp prepare(%Character{} = character, item_id, quantity) do
    with :ok <- check_enabled(character),
         {:ok, qty} <- parse_quantity(quantity),
         %Item{} = item <- fetch_item(character.story_id, item_id) || {:error, :item_not_found} do
      {:ok, item, qty}
    end
  end

  defp check_enabled(character),
    do: if(enabled?(story_of(character)), do: :ok, else: {:error, :module_disabled})

  defp fetch_item(story_id, id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get_by(Item, id: id, story_id: story_id)
      _ -> nil
    end
  end

  defp fetch_listing(story_id, id) do
    case parse_id(id) do
      {:ok, id} ->
        Repo.one(
          from l in Listing,
            join: s in assoc(l, :shop),
            join: i in assoc(l, :item),
            where: l.id == ^id and s.story_id == ^story_id and i.story_id == ^story_id,
            preload: [shop: s, item: i]
        )

      _ ->
        nil
    end
  end

  defp fetch_recipient(%Character{id: from_id, story_id: story_id}, to_id) do
    with {:ok, id} <- parse_id(to_id),
         %Character{approval_status: "approved"} = to <-
           Repo.get_by(Character, id: id, story_id: story_id) do
      if to.id == from_id, do: {:error, :same_character}, else: {:ok, to}
    else
      _ -> {:error, :recipient_not_found}
    end
  end

  defp transaction(fun) do
    case Repo.transaction(fun) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  # Locks the character rows (in id order, like `Bank`) so concurrent
  # inventory changes of the same characters are serialised.
  defp lock_characters(ids) do
    Repo.all(
      from c in Character,
        where: c.id in ^ids,
        order_by: c.id,
        lock: "FOR UPDATE",
        select: c.id
    )
  end

  defp owned_row!(character_id, item_id) do
    Repo.get_by(CharacterItem, character_id: character_id, item_id: item_id) ||
      Repo.rollback(:not_owned)
  end

  defp add_units!(character_id, %Item{stackable: true} = item, qty) do
    now = now()

    Repo.insert_all(
      CharacterItem,
      [
        %{
          character_id: character_id,
          item_id: item.id,
          quantity: qty,
          equipped: false,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [inc: [quantity: qty], set: [updated_at: now]],
      conflict_target: [:character_id, :item_id]
    )
  end

  defp add_units!(character_id, %Item{stackable: false} = item, qty) do
    if qty != 1 or
         Repo.exists?(
           from ci in CharacterItem,
             where: ci.character_id == ^character_id and ci.item_id == ^item.id
         ),
       do: Repo.rollback(:not_stackable)

    Repo.insert!(%CharacterItem{character_id: character_id, item_id: item.id, quantity: 1})
  end

  defp take_units!(character_id, item_id, qty) do
    row =
      Repo.one(
        from ci in CharacterItem,
          where: ci.character_id == ^character_id and ci.item_id == ^item_id,
          lock: "FOR UPDATE"
      )

    cond do
      is_nil(row) or row.quantity < qty -> Repo.rollback(:not_enough_items)
      row.quantity == qty -> Repo.delete!(row)
      true -> row |> Ecto.Changeset.change(quantity: row.quantity - qty) |> Repo.update!()
    end
  end

  defp log!(character, item, qty, action, actor, opts \\ []) do
    Repo.insert!(%Log{
      story_id: character.story_id,
      character_id: character.id,
      target_character_id: opts[:target] && opts[:target].id,
      item_id: item.id,
      item_name: item.name,
      user_id: user_id(actor),
      quantity: qty,
      action: action,
      note: clean_note(opts[:note])
    })
  end

  defp user_id(%User{id: id}), do: id
  defp user_id(_), do: nil

  defp clean_note(nil), do: nil

  defp clean_note(note) do
    case note |> to_string() |> String.trim() |> String.slice(0, 200) do
      "" -> nil
      note -> note
    end
  end

  defp parse_quantity(quantity) do
    case parse_id(quantity) do
      {:ok, qty} when qty >= 1 and qty <= @max_quantity -> {:ok, qty}
      _ -> {:error, :invalid_quantity}
    end
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp story_of(%Character{story: %Story{} = story}), do: story
  defp story_of(%Character{story_id: story_id}), do: Stories.get_story(story_id)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
