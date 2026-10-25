defmodule TannhauserGate.Stories do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  Stories describe a world (background, customs) and its map of locations.
  Each location doubles as a chat room.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters
  alias TannhauserGate.Modules
  alias TannhauserGate.Repo
  alias TannhauserGate.Stories.{LastLocation, Location, PresenceStatus, Story, StoryMaster}

  ## Stories

  def list_stories do
    Repo.all(from s in Story, order_by: [desc: s.is_default, asc: s.name])
  end

  @doc """
  Lists the stories a user can enter: all the published ones, plus the ones
  they run as GDR admin or master. Platform admins see everything.
  """
  def list_visible_stories(user) do
    Repo.all(
      from s in visible_stories_query(user),
        order_by: [desc: s.is_default, asc: s.name],
        preload: [:owner, :masters]
    )
  end

  @doc "The query behind `list_visible_stories/1`, for further filtering."
  def visible_stories_query(user) do
    cond do
      Accounts.admin?(user) ->
        from(s in Story)

      user ->
        mastered = from m in StoryMaster, where: m.user_id == ^user.id, select: m.story_id

        from s in Story,
          where: s.status == "published" or s.owner_id == ^user.id or s.id in subquery(mastered)

      true ->
        from s in Story, where: s.status == "published"
    end
  end

  @doc """
  The map artwork as a `data:` URI for an SVG `<image>`. Browsers render SVG
  images in secure static mode (no scripts, links or external resources), so
  GM-authored markup can never run in the players' pages.
  """
  def map_artwork_src(%Story{map_svg: svg}) when svg in [nil, ""], do: nil

  def map_artwork_src(%Story{} = story) do
    document =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{story.map_width} #{story.map_height}">) <>
        story.map_svg <> "</svg>"

    "data:image/svg+xml;base64," <> Base.encode64(document)
  end

  @doc "The story run by the given game master, if any."
  def get_owned_story(%User{id: user_id}), do: Repo.get_by(Story, owner_id: user_id)
  def get_owned_story(_), do: nil

  ## Roles and permissions

  @admin_roles [:platform_admin, :gdr_admin]
  @master_roles [:platform_admin, :gdr_admin, :master]

  @doc """
  The role of the user in the story, from the most to the least powerful:

    * `:platform_admin` - a platform admin, who can do everything everywhere;
    * `:gdr_admin` - the story owner (a game master), who configures the GDR;
    * `:master` - a narrator: runs chat, characters and moderation, but cannot
      change the configuration;
    * `:player` - anyone else, when the story is published;
    * `nil` - the user cannot enter the story (a draft they don't run).
  """
  def role(%User{} = user, %Story{} = story) do
    cond do
      Accounts.admin?(user) -> :platform_admin
      Accounts.gm?(user) and story.owner_id == user.id -> :gdr_admin
      master_row?(story, user) -> :master
      story.status == "published" -> :player
      true -> nil
    end
  end

  def role(_, %Story{status: "published"}), do: :player
  def role(_, _), do: nil

  @doc "Whether the role can edit the GDR configuration."
  def admin_role?(role), do: role in @admin_roles

  @doc "Whether the role can narrate and moderate the GDR."
  def master_role?(role), do: role in @master_roles

  @doc "Whether the user can enter the story."
  def accessible?(user, %Story{} = story), do: role(user, story) != nil

  @doc "Whether the user can configure the story: its GDR admin or a platform admin."
  def gdr_admin?(user, %Story{} = story), do: admin_role?(role(user, story))
  def gdr_admin?(_, _), do: false

  @doc """
  Whether the user can narrate and moderate the story: a master, its GDR admin
  or a platform admin.
  """
  def master?(user, %Story{} = story), do: master_role?(role(user, story))
  def master?(_, _), do: false

  defp master_row?(%Story{id: story_id}, %User{id: user_id}) do
    Repo.exists?(from m in StoryMaster, where: m.story_id == ^story_id and m.user_id == ^user_id)
  end

  ## Staff permissions

  @permission_labels [
    can_moderate:
      {dgettext_noop("domain", "Moderate"),
       dgettext_noop("domain", "Delete chat entries and posts, handle reports and sanctions.")},
    can_approve_characters:
      {dgettext_noop("domain", "Approve characters"),
       dgettext_noop("domain", "Review and approve or reject characters.")},
    can_award_xp:
      {dgettext_noop("domain", "Award XP"),
       dgettext_noop("domain", "Hand out XP (also through esiti and quest rewards).")},
    can_manage_esiti_quests:
      {dgettext_noop("domain", "Esiti and quests"),
       dgettext_noop("domain", "Claim and resolve esiti, log quests.")},
    can_manage_economy:
      {dgettext_noop("domain", "Economy"),
       dgettext_noop("domain", "Grant and remove items, adjust money.")},
    can_manage_world:
      {dgettext_noop("domain", "World"),
       dgettext_noop("domain", "Zone events, action difficulty, calendar, weather and boards.")}
  ]

  @doc "The staff permissions, as `{key, label, description}`."
  def permissions do
    for {key, {label, description}} <- @permission_labels,
        do:
          {key, Gettext.dgettext(TannhauserGateWeb.Gettext, "domain", label),
           Gettext.dgettext(TannhauserGateWeb.Gettext, "domain", description)}
  end

  @doc """
  Whether the user holds a staff `permission` (see
  `TannhauserGate.Stories.StoryMaster.permissions/0`) in the story. The GDR
  admin and platform admins hold every permission, masters those flagged on
  their `story_masters` row, everyone else none.
  """
  def can?(user, story, permission) do
    MapSet.member?(permissions(user, story), permission)
  end

  @doc "The set of staff permissions the user holds in the story."
  def permissions(%User{} = user, %Story{} = story) do
    case role(user, story) do
      role when role in @admin_roles ->
        MapSet.new(StoryMaster.permissions())

      :master ->
        row = Repo.get_by(StoryMaster, story_id: story.id, user_id: user.id)
        MapSet.new(for p <- StoryMaster.permissions(), row && Map.get(row, p), do: p)

      _ ->
        MapSet.new()
    end
  end

  def permissions(_, _), do: MapSet.new()

  @doc "The `story_masters` rows of the story with their users, by username."
  def list_master_rows(%Story{id: story_id}) do
    Repo.all(
      from m in StoryMaster,
        join: u in assoc(m, :user),
        where: m.story_id == ^story_id,
        order_by: [asc: u.username],
        preload: [user: u]
    )
  end

  @doc """
  Sets one permission flag of a master of the story. Returns
  `{:ok, story_master}` or `{:error, :not_found}`.
  """
  def set_master_permission(%Story{id: story_id}, user_id, permission, value)
      when is_boolean(value) do
    with true <- permission in StoryMaster.permissions() || {:error, :not_found},
         %StoryMaster{} = row <- Repo.get_by(StoryMaster, story_id: story_id, user_id: user_id) do
      row |> StoryMaster.permissions_changeset(%{permission => value}) |> Repo.update()
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  ## Masters

  @doc "The masters of the story (not including its GDR admin), by username."
  def list_masters(%Story{id: story_id}) do
    Repo.all(
      from u in User,
        join: m in StoryMaster,
        on: m.user_id == u.id,
        where: m.story_id == ^story_id,
        order_by: [asc: u.username]
    )
  end

  @doc """
  Makes the user with the given username a master of the story.

  Returns `{:error, :user_not_found}` for unknown usernames, `{:error, :owner}`
  for the GDR admin (who already has every master power) and
  `{:error, :already_master}` when the user is already a master.
  """
  def add_master(%Story{} = story, username) when is_binary(username) do
    case Accounts.get_user_by_username(username) do
      nil ->
        {:error, :user_not_found}

      %User{id: id} when id == story.owner_id ->
        {:error, :owner}

      %User{} = user ->
        %StoryMaster{story_id: story.id, user_id: user.id}
        |> StoryMaster.changeset()
        |> Repo.insert()
        |> case do
          {:ok, _} -> {:ok, user}
          {:error, _changeset} -> {:error, :already_master}
        end
    end
  end

  @doc "Removes a master from the story."
  def remove_master(%Story{id: story_id}, user_id) do
    {count, _} =
      Repo.delete_all(
        from m in StoryMaster, where: m.story_id == ^story_id and m.user_id == ^user_id
      )

    if count > 0, do: :ok, else: {:error, :not_found}
  end

  @doc "A human readable message for `add_master/2` and `remove_master/2` errors."
  def master_error_message(:user_not_found), do: dgettext("domain", "No user with that username.")

  def master_error_message(:owner),
    do: dgettext("domain", "The GDR admin already has every master power.")

  def master_error_message(:already_master),
    do: dgettext("domain", "That user is already a master.")

  def master_error_message(:not_found),
    do: dgettext("domain", "That user is not a master of this GDR.")

  @doc """
  Updates a story through the game master changeset.
  """
  def update_story_as_gm(%Story{} = story, attrs) do
    story |> Story.gm_changeset(attrs) |> Repo.update()
  end

  @doc """
  Sets the directory banner of the story to an uploaded image path (see
  `TannhauserGate.Storage`), or removes it with `nil`.
  """
  def set_banner(%Story{} = story, path) when is_binary(path) or is_nil(path) do
    story |> Story.banner_changeset(path) |> Repo.update()
  end

  def change_story_as_gm(%Story{} = story, attrs \\ %{}), do: Story.gm_changeset(story, attrs)

  ## Optional modules

  @doc """
  Whether the optional module `key` (see `TannhauserGate.Modules`) is enabled
  in the story.
  """
  def module_enabled?(%Story{modules: modules}, key), do: Modules.enabled?(modules, key)
  def module_enabled?(_, _), do: false

  @doc "Turns the optional module `key` on or off for the story."
  def set_module_enabled(%Story{} = story, key, enabled?) when is_boolean(enabled?) do
    if Modules.module?(key) do
      modules = Map.put(story.modules || %{}, to_string(key), enabled?)
      story |> Story.modules_changeset(modules) |> Repo.update()
    else
      {:error, :unknown_module}
    end
  end

  def get_story!(id), do: Story |> Repo.get!(id) |> Repo.preload(:locations)

  def get_story(id), do: Repo.get(Story, id)

  @doc """
  Returns the default story (the one flagged `is_default`, or the oldest one).
  """
  def get_default_story do
    query =
      from s in Story, order_by: [desc: s.is_default, asc: s.inserted_at, asc: s.id], limit: 1

    case Repo.one(query) do
      nil -> nil
      story -> Repo.preload(story, :locations)
    end
  end

  def get_story_by_name(name), do: Repo.get_by(Story, name: name)

  @doc "Creates a story with its default \"Active\" character state."
  def create_story(attrs \\ %{}) do
    Repo.transaction(fn ->
      with {:ok, story} <- %Story{} |> Story.changeset(attrs) |> Repo.insert(),
           {:ok, _state} <- Characters.create_default_states(story) do
        story
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> tap_default()
  end

  def update_story(%Story{} = story, attrs) do
    story
    |> Story.changeset(attrs)
    |> Repo.update()
    |> tap_default()
  end

  def delete_story(%Story{} = story), do: Repo.delete(story)

  def change_story(%Story{} = story, attrs \\ %{}), do: Story.changeset(story, attrs)

  # Only one story can be the default: unset the flag on all the others.
  defp tap_default({:ok, %Story{is_default: true, id: id}} = result) do
    Repo.update_all(from(s in Story, where: s.id != ^id and s.is_default),
      set: [is_default: false]
    )

    result
  end

  defp tap_default(result), do: result

  ## Locations

  def list_locations(%Story{id: story_id}) do
    Repo.all(from l in Location, where: l.story_id == ^story_id, order_by: [asc: l.name])
  end

  def list_all_locations do
    Repo.all(from l in Location, order_by: [asc: l.story_id, asc: l.name], preload: :story)
  end

  def get_location!(id), do: Location |> Repo.get!(id) |> Repo.preload(:story)

  def create_location(%Story{} = story, attrs \\ %{}) do
    %Location{story_id: story.id}
    |> Location.changeset(attrs)
    |> validate_zone()
    |> validate_guild()
    |> Repo.insert()
  end

  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> validate_zone()
    |> validate_guild()
    |> Repo.update()
  end

  # A location may only belong to a zone of its own story.
  defp validate_zone(changeset) do
    story_id = Ecto.Changeset.get_field(changeset, :story_id)

    Ecto.Changeset.validate_change(changeset, :zone_id, fn :zone_id, zone_id ->
      if Repo.exists?(
           from z in TannhauserGate.Zones.Zone,
             where: z.id == ^zone_id and z.story_id == ^story_id
         ),
         do: [],
         else: [zone_id: dgettext_noop("errors", "is not a zone of this story")]
    end)
  end

  # A location may only be restricted to a guild of its own story.
  defp validate_guild(changeset) do
    story_id = Ecto.Changeset.get_field(changeset, :story_id)

    Ecto.Changeset.validate_change(changeset, :guild_id, fn :guild_id, guild_id ->
      if Repo.exists?(
           from g in TannhauserGate.Guilds.Guild,
             where: g.id == ^guild_id and g.story_id == ^story_id
         ),
         do: [],
         else: [guild_id: dgettext_noop("errors", "is not a guild of this story")]
    end)
  end

  def delete_location(%Location{} = location), do: Repo.delete(location)

  def change_location(%Location{} = location, attrs \\ %{}),
    do: Location.changeset(location, attrs)

  ## Return to chat

  @doc "Remembers `location` as the last chat room the user visited in its GDR."
  def remember_location(%User{id: user_id}, %Location{id: location_id, story_id: story_id}) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      LastLocation,
      [
        %{
          user_id: user_id,
          story_id: story_id,
          location_id: location_id,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [set: [location_id: location_id, updated_at: now]],
      conflict_target: [:user_id, :story_id]
    )

    :ok
  end

  def remember_location(_, _), do: :ok

  @doc "The last chat room the user visited in the GDR, if any."
  def last_location(%User{id: user_id}, story_id) do
    Repo.one(
      from ll in LastLocation,
        join: l in assoc(ll, :location),
        where: ll.user_id == ^user_id and ll.story_id == ^story_id and l.story_id == ^story_id,
        select: l
    )
  end

  def last_location(_, _), do: nil

  ## Presence status

  @doc "The presence statuses a user can show in a GDR."
  def presence_statuses, do: PresenceStatus.statuses()

  @doc "The presence status the user picked in the GDR (`\"available\"` by default)."
  def presence_status(%User{id: user_id}, story_id) do
    Repo.one(
      from p in PresenceStatus,
        where: p.user_id == ^user_id and p.story_id == ^story_id,
        select: p.status
    ) || "available"
  end

  def presence_status(_, _), do: "available"

  @doc """
  Saves the presence status of the user in the GDR. Returns `{:ok, status}`
  or `{:error, :invalid_status}`.
  """
  def set_presence_status(%User{id: user_id}, story_id, status) when is_integer(story_id) do
    if status in PresenceStatus.statuses() do
      now = DateTime.utc_now(:second)

      Repo.insert_all(
        PresenceStatus,
        [
          %{
            user_id: user_id,
            story_id: story_id,
            status: status,
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: [set: [status: status, updated_at: now]],
        conflict_target: [:user_id, :story_id]
      )

      {:ok, status}
    else
      {:error, :invalid_status}
    end
  end
end
