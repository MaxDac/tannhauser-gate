defmodule TannhauserGate.Forum.Section do
  use Ecto.Schema
  import Ecto.Changeset

  @visibilities ~w(all approved masters)

  schema "forum_sections" do
    field :name, :string
    field :description, :string
    field :position, :integer, default: 0
    # On-game sections are written in character; off-game ones as the user.
    field :on_game, :boolean, default: false
    # Who can see the section: everyone, only users with an approved
    # character, or only the masters.
    field :visibility, :string, default: "all"

    belongs_to :story, TannhauserGate.Stories.Story
    has_many :topics, TannhauserGate.Forum.Topic

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  @doc false
  def changeset(section, attrs) do
    section
    |> cast(attrs, [:name, :description, :position, :on_game, :visibility])
    |> validate_required([:name, :visibility])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint(:name, name: :forum_sections_story_id_name_index)
  end
end

defmodule TannhauserGate.Forum.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forum_topics" do
    field :title, :string
    field :locked, :boolean, default: false
    field :pinned, :boolean, default: false
    field :post_count, :integer, virtual: true, default: 0
    field :last_post_id, :integer, virtual: true
    field :unread, :boolean, virtual: true, default: false

    belongs_to :section, TannhauserGate.Forum.Section
    belongs_to :user, TannhauserGate.Accounts.User
    belongs_to :character, TannhauserGate.Characters.Character
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

  @doc false
  def flags_changeset(topic, attrs), do: cast(topic, attrs, [:locked, :pinned])
end

defmodule TannhauserGate.Forum.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forum_posts" do
    field :body, :string
    field :edited_at, :utc_datetime

    belongs_to :topic, TannhauserGate.Forum.Topic
    belongs_to :user, TannhauserGate.Accounts.User
    belongs_to :character, TannhauserGate.Characters.Character

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
