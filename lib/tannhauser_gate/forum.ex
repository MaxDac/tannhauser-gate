defmodule TannhauserGate.Forum do
  @moduledoc """
  A simple forum: sections -> topics -> posts (posts ordered by creation time).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Forum.{Post, Section, Topic}
  alias TannhauserGate.Repo

  ## Sections

  def list_sections do
    topic_counts =
      from t in Topic,
        group_by: t.section_id,
        select: %{section_id: t.section_id, count: count(t.id)}

    from(s in Section,
      left_join: c in subquery(topic_counts),
      on: c.section_id == s.id,
      order_by: [asc: s.position, asc: s.name],
      select: {s, coalesce(c.count, 0)}
    )
    |> Repo.all()
  end

  def get_section!(id), do: Repo.get!(Section, id)

  def create_section(attrs \\ %{}) do
    %Section{}
    |> Section.changeset(attrs)
    |> Repo.insert()
  end

  def update_section(%Section{} = section, attrs) do
    section
    |> Section.changeset(attrs)
    |> Repo.update()
  end

  def delete_section(%Section{} = section), do: Repo.delete(section)

  def change_section(%Section{} = section, attrs \\ %{}), do: Section.changeset(section, attrs)

  ## Topics

  @doc """
  Lists topics of a section, most recently created first, with post counts.
  """
  def list_topics(%Section{id: section_id}) do
    from(t in Topic,
      left_join: p in assoc(t, :posts),
      where: t.section_id == ^section_id,
      group_by: t.id,
      order_by: [desc: t.inserted_at, desc: t.id],
      select_merge: %{post_count: count(p.id)},
      preload: [:user]
    )
    |> Repo.all()
  end

  def get_topic!(id), do: Topic |> Repo.get!(id) |> Repo.preload([:section, :user])

  def change_topic(%Topic{} = topic, attrs \\ %{}), do: Topic.changeset(topic, attrs)

  @doc """
  Creates a topic and its opening post in a single transaction.

  Returns `{:ok, topic}` or `{:error, changeset}` (a topic or post changeset).
  """
  def create_topic(%User{} = user, %Section{} = section, attrs) do
    Multi.new()
    |> Multi.insert(
      :topic,
      Topic.changeset(%Topic{section_id: section.id, user_id: user.id}, attrs)
    )
    |> Multi.insert(:post, fn %{topic: topic} ->
      Post.changeset(%Post{topic_id: topic.id, user_id: user.id}, %{
        body: attrs["body"] || attrs[:body]
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{topic: topic}} -> {:ok, topic}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  def delete_topic(%Topic{} = topic), do: Repo.delete(topic)

  ## Posts

  @doc """
  Lists the posts of a topic ordered by creation time (oldest first).
  """
  def list_posts(%Topic{id: topic_id}) do
    Repo.all(
      from p in Post,
        where: p.topic_id == ^topic_id,
        order_by: [asc: p.inserted_at, asc: p.id],
        preload: [:user]
    )
  end

  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  def create_post(%User{} = user, %Topic{} = topic, attrs) do
    %Post{topic_id: topic.id, user_id: user.id}
    |> Post.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, post} -> {:ok, %{post | user: user}}
      error -> error
    end
  end

  def get_post!(id), do: Repo.get!(Post, id)

  def delete_post(%Post{} = post), do: Repo.delete(post)
end
