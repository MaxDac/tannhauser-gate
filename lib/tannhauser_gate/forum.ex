defmodule TannhauserGate.Forum do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  The GDR forum: sections -> topics -> posts (posts ordered by creation time).

  Every section is configured by the GDR admin:

    * `on_game` - on-game sections are written in character: topics and posts
      are authored as one of the characters the user can act as (so the
      character must be able to play); off-game sections are written as the
      user;
    * `visibility` - `"all"` members, only users with an `"approved"`
      character, only the `"masters"`, or only the members of a `"guild"`
      (guilds module: the owners of its active member characters and the
      masters; masters only while the module is disabled).

  Authors edit and delete their own topics and posts; masters moderate the
  whole forum (edit, delete, lock and pin). Read markers are tracked per user
  and topic, by the id of the latest post seen.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Ecto.Multi
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Forum.{Post, Read, Section, Topic}
  alias TannhauserGate.Guilds
  alias TannhauserGate.Guilds.Guild
  alias TannhauserGate.Repo
  alias TannhauserGate.Sanctions
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  ## Sections

  @doc """
  Lists the sections of a story with their topic counts; with `nil`, all of them.
  """
  def list_sections(story \\ nil) do
    query =
      from(s in Section,
        left_join: c in subquery(topic_counts()),
        on: c.section_id == s.id,
        order_by: [asc: s.position, asc: s.name],
        select: {s, coalesce(c.count, 0)}
      )

    query =
      case story do
        %{id: story_id} -> where(query, [s], s.story_id == ^story_id)
        _ -> query
      end

    Repo.all(query)
  end

  @doc """
  The sections of the story the user can see, each as a map with the
  `:section`, its `:topic_count` and the number of topics unread by the user
  (`:unread_count`).
  """
  def list_visible_sections(%User{} = user, %Story{} = story) do
    unread =
      from(t in subquery(topic_last_posts()),
        left_join: r in Read,
        on: r.topic_id == t.topic_id and r.user_id == ^user.id,
        where: is_nil(r.id) or t.last_post_id > r.last_read_post_id,
        group_by: t.section_id,
        select: %{section_id: t.section_id, count: count(t.topic_id)}
      )

    from(s in Section,
      left_join: c in subquery(topic_counts()),
      on: c.section_id == s.id,
      left_join: u in subquery(unread),
      on: u.section_id == s.id,
      where: s.story_id == ^story.id,
      order_by: [asc: s.position, asc: s.name],
      select: %{section: s, topic_count: coalesce(c.count, 0), unread_count: coalesce(u.count, 0)}
    )
    |> Repo.all()
    |> Enum.filter(&can_view_section?(user, story, &1.section))
  end

  defp topic_counts do
    from t in Topic,
      group_by: t.section_id,
      select: %{section_id: t.section_id, count: count(t.id)}
  end

  defp topic_last_posts do
    from t in Topic,
      join: p in assoc(t, :posts),
      group_by: t.id,
      select: %{topic_id: t.id, section_id: t.section_id, last_post_id: max(p.id)}
  end

  @doc """
  Whether the user can see (and so read and write in) the section: everyone
  for `"all"`, masters and users with an approved character for
  `"approved"`, only masters for `"masters"`, masters and the owners of the
  guild's active members for `"guild"` (only masters when the guilds module
  is off).
  """
  def can_view_section?(user, %Story{} = story, %Section{visibility: visibility} = section) do
    case visibility do
      "all" -> true
      "approved" -> Stories.master?(user, story) or approved_member?(user, story)
      "masters" -> Stories.master?(user, story)
      "guild" -> Stories.master?(user, story) or guild_member?(user, story, section)
      _ -> false
    end
  end

  defp guild_member?(user, story, %Section{guild_id: guild_id}),
    do: Guilds.enabled?(story) and Guilds.active_member_user?(user, guild_id)

  defp approved_member?(%User{id: user_id}, %Story{id: story_id}) do
    Repo.exists?(
      from c in Character,
        where:
          c.user_id == ^user_id and c.story_id == ^story_id and not c.is_npc and
            c.approval_status == "approved"
    )
  end

  defp approved_member?(_, _), do: false

  @doc "A short label for a section visibility."
  def visibility_label("all"), do: dgettext("domain", "All members")
  def visibility_label("approved"), do: dgettext("domain", "Approved characters")
  def visibility_label("masters"), do: dgettext("domain", "Masters only")
  def visibility_label("guild"), do: dgettext("domain", "Guild members")
  def visibility_label(other), do: other

  def get_section!(id), do: Repo.get!(Section, id)

  def create_section(%{id: story_id}, attrs) do
    %Section{story_id: story_id}
    |> Section.changeset(attrs)
    |> validate_story_guild()
    |> Repo.insert()
  end

  def update_section(%Section{} = section, attrs) do
    section
    |> Section.changeset(attrs)
    |> validate_story_guild()
    |> Repo.update()
  end

  # A guild section may only belong to a guild of its own story.
  defp validate_story_guild(changeset) do
    story_id = Changeset.get_field(changeset, :story_id)

    Changeset.validate_change(changeset, :guild_id, fn :guild_id, guild_id ->
      if Repo.exists?(from g in Guild, where: g.id == ^guild_id and g.story_id == ^story_id),
        do: [],
        else: [guild_id: dgettext_noop("errors", "is not a guild of this GDR")]
    end)
  end

  def delete_section(%Section{} = section), do: Repo.delete(section)

  def change_section(%Section{} = section, attrs \\ %{}), do: Section.changeset(section, attrs)

  ## Topics

  @doc """
  Lists topics of a section, pinned first then by latest activity, with post
  counts. With a user, every topic also tells whether it is `unread` for them.
  """
  def list_topics(%Section{id: section_id}, user \\ nil) do
    topics =
      from(t in Topic,
        left_join: p in assoc(t, :posts),
        where: t.section_id == ^section_id,
        group_by: t.id,
        order_by: [desc: t.pinned, desc: max(p.id), desc: t.id],
        select_merge: %{post_count: count(p.id), last_post_id: max(p.id)},
        preload: [:user, :character]
      )
      |> Repo.all()

    mark_unread(topics, user)
  end

  defp mark_unread(topics, %User{id: user_id}) do
    ids = Enum.map(topics, & &1.id)

    reads =
      Repo.all(
        from r in Read,
          where: r.user_id == ^user_id and r.topic_id in ^ids,
          select: {r.topic_id, r.last_read_post_id}
      )
      |> Map.new()

    Enum.map(topics, fn topic ->
      %{topic | unread: (topic.last_post_id || 0) > Map.get(reads, topic.id, 0)}
    end)
  end

  defp mark_unread(topics, _), do: topics

  def get_topic!(id),
    do: Topic |> Repo.get!(id) |> Repo.preload([:section, :user, :character])

  def change_topic(%Topic{} = topic, attrs \\ %{}), do: Topic.changeset(topic, attrs)

  @doc """
  Creates a topic and its opening post in a single transaction. In on-game
  sections both are authored as `attrs["character_id"]`, which must be a
  character the user can act as.

  Returns `{:ok, topic}`, `{:error, :muted}`, `{:error, :unauthorized}` when the user cannot see
  the section, or `{:error, changeset}` (a topic or post changeset).
  """
  def create_topic(%User{} = user, %Section{} = section, attrs) do
    story = story_of(section)

    cond do
      not can_view_section?(user, story, section) -> {:error, :unauthorized}
      Sanctions.muted?(user, story) -> {:error, :muted}
      true -> do_create_topic(user, section, attrs)
    end
  end

  defp do_create_topic(user, section, attrs) do
    {character_id, character_error} = author_character(user, section, attrs)

    topic_changeset =
      %Topic{section_id: section.id, user_id: user.id, character_id: character_id}
      |> Topic.changeset(attrs)
      |> put_character_error(character_error)

    Multi.new()
    |> Multi.insert(:topic, topic_changeset)
    |> Multi.insert(:post, fn %{topic: topic} ->
      Post.changeset(%Post{topic_id: topic.id, user_id: user.id, character_id: character_id}, %{
        body: get_attr(attrs, :body)
      })
    end)
    |> Multi.run(:read, fn _repo, %{topic: topic, post: post} ->
      {:ok, upsert_read(user, topic, post.id)}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{topic: topic}} -> {:ok, topic}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Whether the user can edit or delete the topic: its author or a moderator."
  def can_edit_topic?(%User{id: user_id} = user, %Story{} = story, %Topic{} = topic),
    do: topic.user_id == user_id or Stories.can?(user, story, :can_moderate)

  def can_edit_topic?(_, _, _), do: false

  @doc "Renames a topic, if the user can edit it."
  def update_topic(user, %Story{} = story, %Topic{} = topic, attrs) do
    cond do
      not can_edit_topic?(user, story, topic) -> {:error, :unauthorized}
      muted_author?(user, story) -> {:error, :muted}
      true -> topic |> Topic.changeset(attrs) |> Repo.update()
    end
  end

  # Moderators may still fix content; everyone else is blocked while muted.
  defp muted_author?(user, story),
    do: not Stories.can?(user, story, :can_moderate) and Sanctions.muted?(user, story)

  @doc """
  Locks/unlocks or pins/unpins a topic (`"locked"`, `"pinned"`): masters only.
  Locked topics accept new posts only from masters. Moderators only
  (`Stories.can?(user, story, :can_moderate)`).
  """
  def set_topic_flags(user, %Story{} = story, %Topic{} = topic, attrs) do
    if Stories.can?(user, story, :can_moderate) do
      topic |> Topic.flags_changeset(attrs) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @doc "Deletes a topic (and its posts), if the user can edit it."
  def delete_topic(user, %Story{} = story, %Topic{} = topic) do
    if can_edit_topic?(user, story, topic), do: delete_topic(topic), else: {:error, :unauthorized}
  end

  def delete_topic(%Topic{} = topic), do: Repo.delete(topic)

  ## Read markers

  @doc "Marks every current post of the topic as read by the user."
  def mark_topic_read(%User{} = user, %Topic{id: topic_id} = topic) do
    last =
      Repo.one(from p in Post, where: p.topic_id == ^topic_id, select: max(p.id))

    upsert_read(user, topic, last || 0)
  end

  defp upsert_read(%User{id: user_id}, %Topic{id: topic_id}, post_id) do
    now = DateTime.utc_now(:second)

    Repo.insert!(
      %Read{user_id: user_id, topic_id: topic_id, last_read_post_id: post_id, updated_at: now},
      on_conflict:
        from(r in Read,
          update: [
            set: [
              last_read_post_id:
                fragment("GREATEST(?, EXCLUDED.last_read_post_id)", r.last_read_post_id),
              updated_at: ^now
            ]
          ]
        ),
      conflict_target: [:user_id, :topic_id]
    )
  end

  ## Posts

  @doc """
  Lists the posts of a topic ordered by creation time (oldest first).
  """
  def list_posts(%Topic{id: topic_id}) do
    Repo.all(
      from p in Post,
        where: p.topic_id == ^topic_id,
        order_by: [asc: p.inserted_at, asc: p.id],
        preload: [:user, :character]
    )
  end

  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  @doc """
  Replies to a topic. In on-game sections the post is authored as
  `attrs["character_id"]`, which must be a character the user can act as.
  Locked topics accept replies only from masters.

  Returns `{:ok, post}`, `{:error, :unauthorized}`, `{:error, :locked}`, `{:error, :muted}` or
  `{:error, changeset}`.
  """
  def create_post(%User{} = user, %Topic{} = topic, attrs) do
    topic = Repo.preload(topic, :section)
    story = story_of(topic.section)

    cond do
      not can_view_section?(user, story, topic.section) ->
        {:error, :unauthorized}

      topic.locked and not Stories.master?(user, story) ->
        {:error, :locked}

      Sanctions.muted?(user, story) ->
        {:error, :muted}

      true ->
        do_create_post(user, topic, attrs)
    end
  end

  defp do_create_post(user, topic, attrs) do
    {character_id, character_error} = author_character(user, topic.section, attrs)

    %Post{topic_id: topic.id, user_id: user.id, character_id: character_id}
    |> Post.changeset(attrs)
    |> put_character_error(character_error)
    |> Repo.insert()
    |> case do
      {:ok, post} ->
        upsert_read(user, topic, post.id)
        {:ok, Repo.preload(%{post | user: user}, :character)}

      error ->
        error
    end
  end

  @doc "Whether the user can edit or delete the post: its author or a moderator."
  def can_edit_post?(%User{id: user_id} = user, %Story{} = story, %Post{} = post),
    do: post.user_id == user_id or Stories.can?(user, story, :can_moderate)

  def can_edit_post?(_, _, _), do: false

  @doc "Edits the body of a post, if the user can edit it, stamping `edited_at`."
  def update_post(user, %Story{} = story, %Post{} = post, attrs) do
    cond do
      not can_edit_post?(user, story, post) ->
        {:error, :unauthorized}

      muted_author?(user, story) ->
        {:error, :muted}

      true ->
        post
        |> Post.changeset(attrs)
        |> Changeset.put_change(:edited_at, DateTime.utc_now(:second))
        |> Repo.update()
    end
  end

  @doc "Deletes a post, if the user can edit it."
  def delete_post(user, %Story{} = story, %Post{} = post) do
    if can_edit_post?(user, story, post), do: delete_post(post), else: {:error, :unauthorized}
  end

  def get_post!(id), do: Repo.get!(Post, id)

  @doc "The display name of a post or topic author: its character, or the user."
  def author_name(%{character: %Character{name: name}}), do: name
  def author_name(%{user: %User{} = user}), do: User.handle(user)
  def author_name(_), do: "unknown"

  @doc """
  The latest `limit` posts of every section of a story, newest first, with
  their topic and author (used by the master moderation tools).
  """
  def list_story_posts(story_id, limit \\ 50) do
    Repo.all(
      from p in Post,
        join: t in assoc(p, :topic),
        join: s in assoc(t, :section),
        where: s.story_id == ^story_id,
        order_by: [desc: p.inserted_at, desc: p.id],
        limit: ^limit,
        preload: [:user, :character, topic: t]
    )
  end

  @doc "Gets a post of the given story, or `nil`."
  def get_story_post(story_id, id) do
    Repo.one(
      from p in Post,
        join: t in assoc(p, :topic),
        join: s in assoc(t, :section),
        where: p.id == ^id and s.story_id == ^story_id
    )
  end

  def delete_post(%Post{} = post), do: Repo.delete(post)

  ## Authoring helpers

  # Off-game sections are always written as the user; on-game ones need a
  # character the user can act as (which implies the character can play).
  defp author_character(_user, %Section{on_game: false}, _attrs), do: {nil, nil}

  defp author_character(user, %Section{on_game: true, story_id: story_id}, attrs) do
    with id when is_integer(id) <- to_id(get_attr(attrs, :character_id)),
         %Character{story_id: ^story_id} = character <- Characters.get_character(id),
         true <- Characters.can_act_as?(user, character) do
      {character.id, nil}
    else
      _ -> {nil, dgettext_noop("errors", "choose a character that can play")}
    end
  end

  defp put_character_error(changeset, nil), do: changeset

  defp put_character_error(changeset, message),
    do: Changeset.add_error(changeset, :character_id, message)

  defp get_attr(attrs, key), do: attrs[Atom.to_string(key)] || attrs[key]

  defp to_id(id) when is_integer(id), do: id

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_id(_), do: nil

  defp story_of(%Section{story_id: story_id}), do: Repo.get!(Story, story_id)
end
