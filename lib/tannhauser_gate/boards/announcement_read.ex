defmodule TannhauserGate.Boards.AnnouncementRead do
  @moduledoc "When a user last saw the announcements of a GDR (for the unread badge)."
  use Ecto.Schema

  schema "announcement_reads" do
    field :last_seen_at, :utc_datetime_usec

    belongs_to :user, TannhauserGate.Accounts.User
    belongs_to :story, TannhauserGate.Stories.Story
  end
end
