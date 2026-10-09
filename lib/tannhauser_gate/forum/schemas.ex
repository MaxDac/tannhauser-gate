defmodule TannhauserGate.Forum.Section do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forum_sections" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0

    belongs_to :story, TannhauserGate.Stories.Story
    has_many :topics, TannhauserGate.Forum.Topic

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:name, :description, :position])
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> unique_constraint(:name, name: :forum_sections_story_id_name_index)
  end
end

defmodule TannhauserGate.Forum.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forum_topics" do
    field :title, :string
    field :post_count, :integer, virtual: true, default: 0

    belongs_to :section, TannhauserGate.Forum.Section
    belongs_to :user, TannhauserGate.Accounts.User
    has_many :posts, TannhauserGate.Forum.Post

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:title])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
  end
end

defmodule TannhauserGate.Forum.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forum_posts" do
    field :body, :string

    belongs_to :topic, TannhauserGate.Forum.Topic
    belongs_to :user, TannhauserGate.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, max: 20_000)
  end
end
