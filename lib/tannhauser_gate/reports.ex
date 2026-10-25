defmodule TannhauserGate.Reports do
  @moduledoc """
  Reports, part of the `:reports` optional module. Any member of a GDR can
  report a chat entry (`"chat"`), a forum post (`"forum_post"`), a letter they
  received (`"mail"`), a notice (`"notice"`, boards module) or a character
  (`"character"`), picking a category and an optional free text.

  The target must belong to the GDR and be visible to the reporter, and
  nobody can report their own content. Its text is snapshotted into the
  report, since it may be deleted later. A user has at most one open report
  per target and files at most 10 reports per hour in a GDR.

  The moderators (`Stories.can?(user, story, :can_moderate)`) resolve or
  dismiss reports with notes, optionally deleting the reported content (chat
  entries, forum posts and notices).
  """

  import Ecto.Query, warn: false

  alias TannhauserGate.Accounts.User
  alias TannhauserGate.Boards
  alias TannhauserGate.Bookings
  alias TannhauserGate.Characters
  alias TannhauserGate.Characters.Character
  alias TannhauserGate.Chat
  alias TannhauserGate.Forum
  alias TannhauserGate.Mailbox
  alias TannhauserGate.Repo
  alias TannhauserGate.Reports.Report
  alias TannhauserGate.Stories
  alias TannhauserGate.Stories.Story

  @hourly_limit 10
  @snapshot_max 5_000
  @preloads [:reporter, :target_user, :handled_by]

  @doc "Whether reports are enabled in the story (the `:reports` module)."
  def enabled?(%Story{} = story), do: Stories.module_enabled?(story, :reports)
  def enabled?(_), do: false

  @doc "The report categories, as `{label, value}` select options."
  def category_options do
    [
      {"Harassment", "harassment"},
      {"Spam", "spam"},
      {"Metagame", "metagame"},
      {"Rules violation", "rules"},
      {"Other", "other"}
    ]
  end

  def category_label(category) do
    case List.keyfind(category_options(), category, 1) do
      {label, _} -> label
      nil -> category
    end
  end

  def target_type_label("chat"), do: "Chat entry"
  def target_type_label("forum_post"), do: "Forum post"
  def target_type_label("mail"), do: "Letter"
  def target_type_label("notice"), do: "Notice"
  def target_type_label("character"), do: "Character"
  def target_type_label(other), do: other

  def status_label("open"), do: "Open"
  def status_label("resolved"), do: "Resolved"
  def status_label("dismissed"), do: "Dismissed"
  def status_label(other), do: other

  @doc "Whether the reported content of the report can be deleted from the queue."
  def deletable?(%Report{target_type: type}), do: type in ~w(chat forum_post notice)

  ## Filing

  def change_report(attrs \\ %{}), do: Report.changeset(%Report{}, attrs)

  @doc """
  Files a report. `attrs` (string keys): `"target_type"`, `"target_id"`,
  `"category"` and the optional `"reason"`.

  Errors: `:module_disabled`, `:unauthorized` (the user cannot enter the
  GDR), `:invalid_target`, `:target_not_found` (missing, of another GDR or
  not visible), `:own_content`, `:rate_limited`, `:duplicate` or a changeset.
  """
  def create_report(%User{} = user, %Story{} = story, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    type = attrs["target_type"]

    with :ok <- check_enabled(story),
         true <- Stories.accessible?(user, story) || {:error, :unauthorized},
         true <- type in Report.target_types() || {:error, :invalid_target},
         id when is_integer(id) <- to_id(attrs["target_id"]) || {:error, :target_not_found},
         {:ok, target} <- fetch_target(type, user, story, id),
         true <- target.author_id != user.id || {:error, :own_content},
         :ok <- check_rate(user, story) do
      %Report{
        story_id: story.id,
        reporter_id: user.id,
        target_type: type,
        target_id: id,
        target_user_id: target.author_id,
        target_label: String.slice(target.label, 0, 255),
        content_snapshot: String.slice(target.snapshot || "", 0, @snapshot_max)
      }
      |> Report.changeset(attrs)
      |> Repo.insert()
      |> duplicate_error()
    end
  end

  defp duplicate_error({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    if Keyword.has_key?(errors, :reporter_id),
      do: {:error, :duplicate},
      else: {:error, changeset}
  end

  defp duplicate_error({:ok, _report} = ok), do: ok

  @doc """
  What the user would report: `{:ok, %{author_id, label, snapshot}}` when the
  target belongs to the story and the user can see it, or an error (see
  `create_report/3`).
  """
  def preview(%User{} = user, %Story{} = story, type, id) do
    with :ok <- check_enabled(story),
         true <- type in Report.target_types() || {:error, :invalid_target},
         id when is_integer(id) <- to_id(id) || {:error, :target_not_found},
         {:ok, target} <- fetch_target(type, user, story, id),
         true <- target.author_id != user.id || {:error, :own_content},
         true <- not reported?(user, type, id) || {:error, :duplicate} do
      {:ok, target}
    end
  end

  @doc "Whether the user already has an open report on the target."
  def reported?(%User{id: user_id}, type, id) do
    Repo.exists?(
      from r in Report,
        where:
          r.reporter_id == ^user_id and r.target_type == ^type and r.target_id == ^id and
            r.status == "open"
    )
  end

  defp check_rate(%User{id: user_id}, %Story{id: story_id}) do
    since = DateTime.add(DateTime.utc_now(), -3600)

    count =
      Repo.aggregate(
        from(r in Report,
          where: r.reporter_id == ^user_id and r.story_id == ^story_id and r.inserted_at > ^since
        ),
        :count
      )

    if count < @hourly_limit, do: :ok, else: {:error, :rate_limited}
  end

  # Each target resolves to %{author_id, label, snapshot} when it belongs to
  # the story and the user can see it.
  defp fetch_target("chat", user, story, id) do
    viewer = if Stories.master?(user, story), do: :all, else: user

    with %{} = message <- Chat.get_story_message(story.id, id),
         message = Repo.preload(message, [:character, :location, :recipient_character]),
         true <- Chat.visible?(message, viewer),
         true <- viewer == :all or Bookings.can_access?(user, message.location) do
      {:ok,
       %{
         author_id: message.user_id,
         label: "#{Chat.speaker_name(message)} in #{message.location.name}",
         snapshot: message.body
       }}
    else
      _ -> {:error, :target_not_found}
    end
  end

  defp fetch_target("forum_post", user, story, id) do
    with %{} = post <- Forum.get_story_post(story.id, id),
         post = Repo.preload(post, [:user, :character, topic: :section]),
         true <- Forum.can_view_section?(user, story, post.topic.section) do
      {:ok,
       %{
         author_id: post.user_id,
         label: "#{Forum.author_name(post)} in \"#{post.topic.title}\"",
         snapshot: post.body
       }}
    else
      _ -> {:error, :target_not_found}
    end
  end

  defp fetch_target("mail", user, story, id) do
    with %{} = message <- Mailbox.get_message(user, story, id),
         true <- Mailbox.in_inbox?(Mailbox.identity(user, story), message) do
      {:ok,
       %{
         author_id: message.sender_user_id,
         label: "Letter from #{message.sender_name}: #{message.subject}",
         snapshot: "#{message.subject}\n\n#{message.body}"
       }}
    else
      _ -> {:error, :target_not_found}
    end
  end

  defp fetch_target("notice", user, story, id) do
    with true <- Boards.enabled?(story),
         %{} = notice <- Boards.get_notice(story, id),
         notice = Repo.preload(notice, [:board, :character]),
         true <- Boards.accessible?(user, story, notice.board) do
      name = (notice.character && notice.character.name) || "unknown"

      {:ok,
       %{
         author_id: notice.user_id,
         label: "Notice by #{name} on #{notice.board.name}",
         snapshot: Enum.join(Enum.reject([notice.title, notice.body], &is_nil/1), "\n\n")
       }}
    else
      _ -> {:error, :target_not_found}
    end
  end

  defp fetch_target("character", user, story, id) do
    with %Character{story_id: story_id} = character when story_id == story.id <-
           Characters.get_character(id),
         true <- character.approval_status == "approved" or Stories.master?(user, story) do
      {:ok,
       %{
         author_id: character.user_id,
         label: "Character #{character.name}",
         snapshot:
           [character.name, character.description, character.background]
           |> Enum.reject(&(&1 in [nil, ""]))
           |> Enum.join("\n\n")
       }}
    else
      _ -> {:error, :target_not_found}
    end
  end

  ## Queue

  @doc """
  The reports of the story, open ones first then newest first. Filters
  (string keys): `"status"` (default `"open"`, `"all"` for every status),
  `"target_type"` and `"category"`.
  """
  def list_reports(%Story{id: story_id}, filters \\ %{}) do
    query =
      from r in Report,
        where: r.story_id == ^story_id,
        order_by: [desc: r.inserted_at, desc: r.id],
        preload: ^@preloads

    status = Map.get(filters, "status", "open")

    query =
      if status in Report.statuses(), do: where(query, [r], r.status == ^status), else: query

    query =
      case filters["target_type"] do
        type when is_binary(type) and type != "" -> where(query, [r], r.target_type == ^type)
        _ -> query
      end

    query =
      case filters["category"] do
        category when is_binary(category) and category != "" ->
          where(query, [r], r.category == ^category)

        _ ->
          query
      end

    Repo.all(query)
  end

  @doc "The number of open reports of the story."
  def open_count(%Story{id: story_id} = story) do
    if enabled?(story) do
      Repo.aggregate(
        from(r in Report, where: r.story_id == ^story_id and r.status == "open"),
        :count
      )
    else
      0
    end
  end

  @doc "A report of the story, or nil."
  def get_report(%Story{id: story_id}, id) do
    case to_id(id) do
      nil ->
        nil

      id ->
        Repo.one(
          from r in Report, where: r.id == ^id and r.story_id == ^story_id, preload: ^@preloads
        )
    end
  end

  def change_resolution(%Report{} = report, attrs \\ %{}),
    do: Report.resolution_changeset(report, attrs)

  @doc """
  Resolves or dismisses an open report (moderators only). `attrs` (string
  keys): `"status"` (`"resolved"` or `"dismissed"`), `"resolution_notes"` and
  `"delete_content"` (`"true"`: deletes the reported chat entry, forum post or
  notice, when it still exists).
  """
  def resolve(%User{} = user, %Story{} = story, %Report{} = report, attrs) do
    with :ok <- check_enabled(story),
         true <- Stories.can?(user, story, :can_moderate) || {:error, :unauthorized},
         true <- report.story_id == story.id || {:error, :not_found},
         true <- report.status == "open" || {:error, :not_open} do
      deleted? = attrs["delete_content"] in ["true", true] and delete_content(user, story, report)

      report
      |> Report.resolution_changeset(attrs)
      |> Ecto.Changeset.change(
        handled_by_id: user.id,
        handled_at: DateTime.utc_now(:second),
        content_deleted: report.content_deleted or deleted?
      )
      |> Repo.update()
      |> case do
        {:ok, report} -> {:ok, Repo.preload(report, @preloads, force: true)}
        error -> error
      end
    end
  end

  defp delete_content(user, story, %Report{target_type: "chat", target_id: id}) do
    case Chat.get_story_message(story.id, id) do
      nil -> false
      message -> match?({:ok, _}, Chat.delete_message(user, message))
    end
  end

  defp delete_content(_user, story, %Report{target_type: "forum_post", target_id: id}) do
    case Forum.get_story_post(story.id, id) do
      nil -> false
      post -> match?({:ok, _}, Forum.delete_post(post))
    end
  end

  defp delete_content(user, story, %Report{target_type: "notice", target_id: id}) do
    case Boards.get_notice(story, id) do
      nil -> false
      notice -> match?({:ok, _}, Boards.delete_notice(user, story, notice))
    end
  end

  defp delete_content(_user, _story, _report), do: false

  def error_message(:module_disabled), do: "Reports are not enabled in this GDR."
  def error_message(:unauthorized), do: "You can't do that."
  def error_message(:invalid_target), do: "That can't be reported."
  def error_message(:target_not_found), do: "That content does not exist or you can't see it."
  def error_message(:own_content), do: "You can't report your own content."
  def error_message(:rate_limited), do: "You filed too many reports: try again later."

  def error_message(:duplicate),
    do: "You already reported this: the masters will look into it."

  def error_message(:not_found), do: "That report does not exist in this GDR."
  def error_message(:not_open), do: "That report was already handled."
  def error_message(%Ecto.Changeset{}), do: "Check the report form."
  def error_message(_), do: "Something went wrong."

  defp check_enabled(story),
    do: if(enabled?(story), do: :ok, else: {:error, :module_disabled})

  defp to_id(id) when is_integer(id), do: id

  defp to_id(id) when is_binary(id) do
    case Integer.parse(String.trim(id)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_id(_), do: nil
end
