defmodule TannhauserGate.Sanctions do
  @moduledoc """
  Sanctions per GDR, part of the `:reports` optional module. The moderators
  (`Stories.can?(user, story, :can_moderate)`) issue:

    * a `warning`: recorded and notified only;
    * a `mute`: the user cannot post anything in the GDR (chat entries of
      every kind, dice included, forum topics and posts, letters, notices,
      esiti and their threads) — every write function checks
      `check_not_muted/2`;
    * a `ban`: the user cannot enter the GDR (`TannhauserGateWeb.UserAuth`
      `:load_story` hook).

  A nil `ends_at` makes a mute or ban permanent. The staff of the GDR (its
  masters, GDR admin and platform admins) cannot be sanctioned and are never
  blocked. Everything is a no-op when the module is disabled.

  The sanctioned user gets a letter from "The masters" (to their character)
  and a flash on the next GDR page they open. The `sanctions` table is the
  audit log: sanctions are revoked, never deleted.
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts
  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Characters
  alias TannhauserGate.Mailbox
  alias TannhauserGate.Repo
  alias TannhauserGate.Reports.Report
  alias TannhauserGate.Sanctions.Sanction
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  @preloads [:user, :issued_by, :revoked_by]

  @durations [
    {"1 hour", "1"},
    {"1 day", "24"},
    {"3 days", "72"},
    {"1 week", "168"},
    {"30 days", "720"},
    {"Permanent", "permanent"}
  ]

  @doc "Whether sanctions are enforced in the story (the `:reports` module)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :reports)
  def enabled?(_), do: false

  @doc "The duration options of mutes and bans, as `{label, hours}` select options."
  def duration_options, do: @durations

  ## Enforcement

  @doc """
  The active sanction of `kind` of the user in the story (the longest lasting
  one), or nil. Always nil when the module is disabled.
  """
  def active_sanction(user, story, kind, now \\ DateTime.utc_now())

  def active_sanction(%User{id: user_id}, %Story{id: story_id} = story, kind, now) do
    if enabled?(story) do
      Repo.one(
        from s in Sanction,
          where:
            s.story_id == ^story_id and s.user_id == ^user_id and s.kind in ^List.wrap(kind) and
              is_nil(s.revoked_at) and s.starts_at <= ^now and
              (is_nil(s.ends_at) or s.ends_at > ^now),
          order_by: [desc_nulls_first: s.ends_at, desc: s.id],
          limit: 1
      )
    end
  end

  def active_sanction(_, _, _, _), do: nil

  @doc "The active ban of the user in the story, or nil (never for the staff)."
  def active_ban(user, story) do
    with %Sanction{} = ban <- active_sanction(user, story, "ban"),
         false <- Stories.master?(user, story) do
      ban
    else
      _ -> nil
    end
  end

  @doc """
  The active mute (or ban) silencing the user in the story, or nil (never for
  the staff).
  """
  def active_mute(user, story) do
    with %Sanction{} = mute <- active_sanction(user, story, ["mute", "ban"]),
         false <- Stories.master?(user, story) do
      mute
    else
      _ -> nil
    end
  end

  @doc "Whether the user is muted (or banned) in the story."
  def muted?(user, story), do: active_mute(user, story) != nil

  @doc """
  `:ok`, or `{:error, :muted}` when the user cannot post in the story. Every
  write function of the GDR contents calls it.
  """
  def check_not_muted(user, %Story{} = story) do
    if muted?(user, story), do: {:error, :muted}, else: :ok
  end

  def check_not_muted(user, story_id) when is_integer(story_id),
    do: check_not_muted(user, Stories.get_story(story_id))

  def check_not_muted(_user, _story), do: :ok

  @doc "A friendly message for a muted user."
  def muted_message(user, story) do
    case active_mute(user, story) do
      nil -> "You cannot post in this GDR right now."
      mute -> "You are #{verb(mute)} in this GDR #{until(mute)}: you cannot post."
    end
  end

  defp verb(%Sanction{kind: "ban"}), do: "banned"
  defp verb(_), do: "muted"

  @doc "\"until <date>\" or \"permanently\"."
  def until(%Sanction{ends_at: nil}), do: "permanently"
  def until(%Sanction{ends_at: at}), do: "until #{format(at)}"

  @doc "A short UTC date and time."
  def format(%DateTime{} = at), do: Calendar.strftime(at, "%d %b %Y, %H:%M UTC")
  def format(_), do: "—"

  ## Notifications

  @doc """
  The sanctions of the user in the story they have not been shown yet; marks
  them seen. Used to flash them on the next page. Empty when disabled.
  """
  def pop_unseen(%User{id: user_id}, %Story{id: story_id} = story) do
    if enabled?(story) do
      sanctions =
        Repo.all(
          from s in Sanction,
            where:
              s.story_id == ^story_id and s.user_id == ^user_id and is_nil(s.seen_at) and
                is_nil(s.revoked_at),
            order_by: [asc: s.id]
        )

      ids = Enum.map(sanctions, & &1.id)

      if ids != [] do
        Repo.update_all(from(s in Sanction, where: s.id in ^ids),
          set: [seen_at: DateTime.utc_now(:second)]
        )
      end

      Enum.filter(sanctions, &(&1.kind == "warning" or Sanction.active?(&1)))
    else
      []
    end
  end

  def pop_unseen(_, _), do: []

  @doc "The text shown to the sanctioned user."
  def notice_text(%Sanction{kind: "warning"} = s),
    do: "The masters issued you a warning: #{s.reason}"

  def notice_text(%Sanction{kind: "mute"} = s),
    do: "You are muted #{until(s)}: you cannot post in this GDR. Reason: #{s.reason}"

  def notice_text(%Sanction{kind: "ban"} = s),
    do: "You are banned from this GDR #{until(s)}. Reason: #{s.reason}"

  ## Issuing

  def change_sanction(attrs \\ %{}), do: Sanction.changeset(%Sanction{}, attrs)

  @doc """
  Issues a sanction. `attrs` (string keys): `"user_id"` or `"username"` (the
  target), `"kind"`, `"reason"`, `"duration"` (hours or `"permanent"`, see
  `duration_options/0`) or an explicit `"ends_at"`, and the optional
  `"report_id"` (a report of the story). Only moderators can do it, and the
  staff cannot be sanctioned.

  Errors: `:module_disabled`, `:unauthorized`, `:user_not_found`, `:staff`,
  or a changeset.
  """
  def issue(%User{} = issuer, %Story{} = story, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with :ok <- check_enabled(story),
         :ok <- check_moderator(issuer, story),
         %User{} = target <- fetch_target(attrs) || {:error, :user_not_found},
         true <- not Stories.master?(target, story) || {:error, :staff} do
      now = DateTime.utc_now(:second)

      %Sanction{
        story_id: story.id,
        user_id: target.id,
        issued_by_id: issuer.id,
        report_id: report_id(story, attrs["report_id"])
      }
      |> Sanction.changeset(
        Map.merge(attrs, %{"starts_at" => now, "ends_at" => ends_at(attrs, now)})
      )
      |> Repo.insert()
      |> case do
        {:ok, sanction} ->
          sanction = Repo.preload(sanction, @preloads)
          notify(sanction, issuer, story)
          {:ok, sanction}

        error ->
          error
      end
    end
  end

  defp fetch_target(%{"user_id" => id}) when id not in [nil, ""] do
    case to_id(id) do
      nil -> nil
      id -> Repo.get(User, id)
    end
  end

  defp fetch_target(%{"username" => username}) when is_binary(username),
    do: Accounts.get_user_by_username(String.trim(username))

  defp fetch_target(_), do: nil

  defp ends_at(%{"kind" => "warning"}, _now), do: nil

  defp ends_at(%{"ends_at" => %DateTime{} = at}, _now), do: at

  defp ends_at(%{"duration" => "permanent"}, _now), do: nil

  defp ends_at(%{"duration" => hours}, now) when is_binary(hours) or is_integer(hours) do
    case to_id(hours) do
      hours when is_integer(hours) and hours > 0 -> DateTime.add(now, hours * 3600)
      _ -> nil
    end
  end

  defp ends_at(attrs, _now), do: attrs["ends_at"]

  defp report_id(%Story{id: story_id}, id) do
    with id when is_integer(id) <- to_id(id),
         true <- Repo.exists?(from r in Report, where: r.id == ^id and r.story_id == ^story_id) do
      id
    else
      _ -> nil
    end
  end

  # A letter from "The masters" to the sanctioned user's character, if any.
  defp notify(%Sanction{} = sanction, issuer, story) do
    case Characters.list_user_characters(sanction.user, story.id) do
      [character | _] ->
        Mailbox.send_from_masters(
          story,
          issuer,
          character,
          subject(sanction),
          notice_text(sanction) <>
            "\n\nIf you think this is a mistake, write to the masters."
        )

      [] ->
        :ok
    end
  end

  defp subject(%Sanction{kind: "warning"}), do: "A warning from the masters"
  defp subject(%Sanction{kind: "mute"}), do: "You have been muted"
  defp subject(%Sanction{kind: "ban"}), do: "You have been banned"

  ## Revoking

  @doc "Revokes an active sanction (moderators only)."
  def revoke(%User{} = user, %Story{} = story, %Sanction{} = sanction) do
    with :ok <- check_enabled(story),
         :ok <- check_moderator(user, story),
         true <- sanction.story_id == story.id || {:error, :not_found},
         true <- is_nil(sanction.revoked_at) || {:error, :already_revoked} do
      sanction
      |> Ecto.Changeset.change(revoked_at: DateTime.utc_now(:second), revoked_by_id: user.id)
      |> Repo.update()
      |> case do
        {:ok, sanction} -> {:ok, Repo.preload(sanction, @preloads, force: true)}
        error -> error
      end
    end
  end

  ## Listing

  @doc """
  The sanctions of the story, newest first. Filters (string keys):
  `"user_id"` (a user's history), `"kind"` and `"status"` (`"active"`).
  """
  def list_sanctions(%Story{id: story_id}, filters \\ %{}) do
    now = DateTime.utc_now()

    query =
      from s in Sanction,
        where: s.story_id == ^story_id,
        order_by: [desc: s.inserted_at, desc: s.id],
        preload: ^@preloads

    Enum.reduce(filters, query, fn
      {"user_id", id}, q when id not in [nil, ""] ->
        where(q, [s], s.user_id == ^(to_id(id) || 0))

      {"kind", kind}, q when kind in ["warning", "mute", "ban"] ->
        where(q, [s], s.kind == ^kind)

      {"status", "active"}, q ->
        where(
          q,
          [s],
          is_nil(s.revoked_at) and s.starts_at <= ^now and
            (is_nil(s.ends_at) or s.ends_at > ^now)
        )

      _, q ->
        q
    end)
    |> Repo.all()
  end

  @doc "A sanction of the story, or nil."
  def get_sanction(%Story{id: story_id}, id) do
    case to_id(id) do
      nil ->
        nil

      id ->
        Repo.one(
          from s in Sanction, where: s.id == ^id and s.story_id == ^story_id, preload: ^@preloads
        )
    end
  end

  @doc "A short status label."
  def status_label(%Sanction{revoked_at: %DateTime{}}), do: "Revoked"

  def status_label(%Sanction{kind: "warning"}), do: "Recorded"

  def status_label(%Sanction{} = s),
    do: if(Sanction.active?(s), do: "Active", else: "Expired")

  def error_message(:module_disabled), do: "Reports and sanctions are not enabled in this GDR."
  def error_message(:unauthorized), do: "Only the moderators can do that."
  def error_message(:user_not_found), do: "No user with that username."
  def error_message(:staff), do: "Masters and GDR admins cannot be sanctioned."
  def error_message(:not_found), do: "That sanction does not exist in this GDR."
  def error_message(:already_revoked), do: "That sanction was already revoked."
  def error_message(%Ecto.Changeset{}), do: "Check the sanction form."
  def error_message(_), do: "Something went wrong."

  ## Helpers

  defp check_enabled(story),
    do: if(enabled?(story), do: :ok, else: {:error, :module_disabled})

  defp check_moderator(user, story),
    do: if(Stories.can?(user, story, :can_moderate), do: :ok, else: {:error, :unauthorized})

  defp to_id(id) when is_integer(id), do: id

  defp to_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_id(_), do: nil
end
