defmodule TannhauserGate.Forum.Read do
  @moduledoc """
  Per-user read marker of a forum topic: the id of the latest post the user
  has seen. A topic is unread when it has a post with a greater id.
  """
  use Ecto.Schema

  schema "forum_reads" do
    field :last_read_post_id, :integer, default: 0

    belongs_to :user, TannhauserGate.Accounts.User
    belongs_to :topic, TannhauserGate.Forum.Topic

    timestamps(type: :utc_datetime, inserted_at: false)
  end
end
